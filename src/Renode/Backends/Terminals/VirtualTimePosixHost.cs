//
// Copyright (c) 2010-2026 Antmicro
//
// This file is licensed under the MIT License.
// Full license text is available in 'licenses/MIT.txt'.
//
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading;

using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.UART;
using Antmicro.Renode.Time;

namespace Antmicro.Renode.Backends.Terminals
{
    public static class VirtualTimePosixHostExtensions
    {
        // Creates a coordinator for a POSIX OpenThread host process built with
        // OPENTHREAD_POSIX_VIRTUAL_TIME. The host is launched separately (ot-cli in VT mode)
        // and connected to the emulated RCP's UART with:
        //   connector Connect sysbus.<usart> <name>
        public static void CreateVirtualTimeHost(this Emulation emulation, string name, int nodeId, int portOffset = 0)
        {
            emulation.ExternalsManager.AddExternal(new VirtualTimePosixHost(nodeId, portOffset), name);
        }
    }

    /// <summary>
    /// Bridges a POSIX OpenThread host process running in OPENTHREAD_POSIX_VIRTUAL_TIME mode to Renode.
    ///
    /// Renode acts as the host's virtual-time coordinator: the host parks on a socket instead of
    /// select()-ing on wall time, and its clock only advances when we deliver an event. We model the
    /// host as a top-level <see cref="ITimeSink"/> on the <see cref="MasterTimeSource"/> so that, while
    /// the host is processing an event in real time, we hold the conservative time barrier
    /// (<see cref="TimeHandle.ReportBackAndBreak"/>) and virtual time cannot leak for the host, its RCP,
    /// or any peer host in the domain.
    ///
    /// Spinel traffic is carried byte-transparently. RCP UART TX (HDLC frames) is coalesced on the
    /// 0x7e flag in <see cref="WriteChar"/> and delivered as OT_SIM_EVENT_RADIO_SPINEL_WRITE. Host TX
    /// (already HDLC-encoded) is injected into the RCP UART RX through <see cref="BackendTerminal"/>'s
    /// flow-controlled path (<see cref="BackendTerminal.CallCharReceived"/>), which paces bytes against
    /// the emulated USART's small RX buffer via BufferStateChanged instead of dumping a whole frame at
    /// once (which would overflow the 3-byte RX FIFO and drop the tail of large frames).
    /// </summary>
    public class VirtualTimePosixHost : BackendTerminal, IDisposable, ITimeSink
    {
        public VirtualTimePosixHost(int nodeId, int portOffset)
        {
            this.nodeId = nodeId;
            // Mirror virtual_time.cpp: sPortOffset = PORT_OFFSET * (kMaxNetworkSize + 1).
            var scaledOffset = portOffset * (KMaxNetworkSize + 1);
            var rcpPort = KRcpBasePort + scaledOffset;
            hostEndPoint = new IPEndPoint(IPAddress.Loopback, KBasePort + scaledOffset + nodeId);

            rcpFrames = new ConcurrentQueue<byte[]>();
            coalesceBuffer = new List<byte>(KMaxEventDataSize);

            socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            socket.Bind(new IPEndPoint(IPAddress.Loopback, rcpPort));

            this.Log(LogLevel.Info, "VirtualTimePosixHost node {0}: listening on 127.0.0.1:{1}, host at 127.0.0.1:{2}",
                nodeId, rcpPort, hostEndPoint.Port);
        }

        public override void AttachTo(IUART uart)
        {
            // The RCP UART must implement IUARTWithBufferState: RX injection is flow-controlled and
            // relies on BufferState/BufferStateChanged to pace bytes against the model's bounded RX
            // FIFO. Without it, BackendTerminal cannot throttle and a small-FIFO model would silently
            // drop the tail of large spinel frames. All in-tree SiLabs USART/EUSART models qualify.
            if(!(uart is IUARTWithBufferState))
            {
                this.Log(LogLevel.Warning,
                    "VirtualTimePosixHost node {0}: {1} does not implement IUARTWithBufferState; " +
                    "RX injection will not be flow-controlled and large spinel frames may be dropped.",
                    nodeId, uart);
            }

            // BackendTerminal wires the flow-controlled RX path (our CallCharReceived -> UART RX,
            // paced by BufferStateChanged) and routes UART TX to our WriteChar override.
            base.AttachTo(uart);

            // Registering the sink assigns TimeHandle, which starts the dispatcher thread.
            EmulationManager.Instance.CurrentEmulation.MasterTimeSource.RegisterSink(this);
            this.Log(LogLevel.Info, "VirtualTimePosixHost node {0}: attached to {1}", nodeId, uart);
        }

        public TimeHandle TimeHandle
        {
            get => handle;
            set
            {
                handle = value;
                dispatcherThread = new Thread(Dispatcher)
                {
                    IsBackground = true,
                    Name = $"VTHost-{nodeId} Dispatcher"
                };
                dispatcherThread.Start();
            }
        }

        public void Dispose()
        {
            disposed = true;
            // Closing the socket breaks a blocking Receive so the dispatcher can exit.
            try { socket?.Close(); } catch { /* ignore */ }
            handle?.Dispose();
            dispatcherThread?.Join(1000);
        }

        // Called on the RCP CPU thread as the emulated USART transmits. Coalesce bytes into whole HDLC
        // frames (delimited by 0x7e) and queue each complete frame for delivery to the host.
        public override void WriteChar(byte value)
        {
            lock(coalesceBuffer)
            {
                if(value == HdlcFlag)
                {
                    if(coalesceHasContent)
                    {
                        var frame = new byte[coalesceBuffer.Count + 2];
                        frame[0] = HdlcFlag;
                        coalesceBuffer.CopyTo(frame, 1);
                        frame[frame.Length - 1] = HdlcFlag;
                        rcpFrames.Enqueue(frame);
                        Dbg($"RCP frame emitted len={frame.Length} queue={rcpFrames.Count} {Hex(frame)}");
                        coalesceBuffer.Clear();
                        coalesceHasContent = false;
                    }
                    // else: lone/opening flag or idle line, ignore.
                }
                else
                {
                    coalesceBuffer.Add(value);
                    coalesceHasContent = true;
                }
            }
        }

        private static string Hex(byte[] data)
        {
            if(data == null)
            {
                return "";
            }
            var n = Math.Min(data.Length, 80);
            var sb = new System.Text.StringBuilder(n * 3);
            for(var i = 0; i < n; i++)
            {
                sb.Append(data[i].ToString("x2"));
                sb.Append(' ');
            }
            if(data.Length > n)
            {
                sb.Append("...");
            }
            return sb.ToString();
        }

        private void Dbg(string msg)
        {
            if(!DebugToFile)
            {
                return;
            }
            try
            {
                System.IO.File.AppendAllText($"/tmp/vthost_{nodeId}.log",
                    $"{DateTime.Now:HH:mm:ss.fff} now={hostNow.TotalMicroseconds:F0}us dl={deadline.TotalMicroseconds:F0}us {msg}\n");
            }
            catch { /* ignore */ }
        }

        private void Dispatcher()
        {
            try
            {
                handle.SinkSideActive = true;
                // Let the rest of the domain (the RCP) free-run while the host process starts up and
                // connects. A disabled handle still tracks virtual time but never blocks the barrier.
                handle.Enabled = false;

                // Block until the host sends its first batch (initial spinel reset + park).
                if(!ReceiveHostBatch())
                {
                    return;
                }

                // Engage lockstep from the current virtual time.
                handle.Enabled = true;
                hostNow = handle.TotalElapsedTime;
                lastDelivered = hostNow;
                deadline = hostNow + pendingDelay;

                while(!disposed)
                {
                    if(!handle.RequestTimeInterval(out var quantum))
                    {
                        if(handle.DetachRequested)
                        {
                            break;
                        }
                        // Paused/interrupted: avoid a tight spin until the source is active again.
                        Thread.Sleep(1);
                        continue;
                    }

                    // 0) Drain any events the host produced spontaneously (e.g. it woke on stdin for a
                    // CLI command and issued a fresh spinel transaction). Without this, a host-initiated
                    // command that arrives while we are advancing would never be injected into the RCP,
                    // and we would run to the park deadline and wake the host with a spurious timeout.
                    if(!DrainPendingHostEvents())
                    {
                        break;
                    }

                    // 1) Deliver a pending RCP->host spinel frame, if any (wakes the host).
                    if(rcpFrames.TryDequeue(out var frame))
                    {
                        handle.ReportBackAndBreak(quantum);
                        SendSpinelToHost(frame);
                        if(!FreezeAndReceiveNextBatch())
                        {
                            break;
                        }
                        continue;
                    }

                    // 2) Park deadline reached with no data -> wake the host with an alarm.
                    if(hostNow >= deadline)
                    {
                        handle.ReportBackAndBreak(quantum);
                        SendAlarmToHost();
                        if(!FreezeAndReceiveNextBatch())
                        {
                            break;
                        }
                        continue;
                    }

                    // 3) Advance one quantum toward the deadline; the RCP executes in parallel.
                    var toDeadline = deadline - hostNow;
                    var use = TimeInterval.Min(quantum, toDeadline);
                    handle.ReportBackAndContinue(quantum - use);
                    hostNow += use;
                }
            }
            catch(Exception e)
            {
                if(!disposed)
                {
                    this.Log(LogLevel.Error, "VirtualTimePosixHost node {0} dispatcher terminated: {1}", nodeId, e);
                }
            }
        }

        // Holds the barrier (via a prior ReportBackAndBreak) while the host processes in real time.
        // Setting SinkSideActive=false lets the master time source sleep instead of busy-spinning;
        // setting it back to true wakes the master (ReportHandleActive) the moment the host re-parks.
        private bool FreezeAndReceiveNextBatch()
        {
            handle.SinkSideActive = false;
            var ok = ReceiveHostBatch(); // sets the new deadline via ProcessEvent
            handle.SinkSideActive = true;
            return ok;
        }

        // Receives a host batch: zero or more RADIO_SPINEL_WRITE frames (injected into the RCP RX)
        // followed by exactly one ALARM_FIRED (park). Blocks. Returns false if the socket was closed.
        private bool ReceiveHostBatch()
        {
            while(true)
            {
                if(!ReceiveEvent(out var eventType, out var delayUs, out var data))
                {
                    return false;
                }
                if(ProcessEvent(eventType, delayUs, data))
                {
                    return true; // park terminates the batch
                }
            }
        }

        // Non-blocking: process every host event currently queued on the socket, if any. Used while
        // advancing so host-initiated (stdin-driven) spinel transactions are injected promptly and
        // their park deadlines are honored. Returns false if the socket was closed.
        private bool DrainPendingHostEvents()
        {
            while(!disposed && socket.Poll(0, SelectMode.SelectRead))
            {
                if(!ReceiveEvent(out var eventType, out var delayUs, out var data))
                {
                    return false;
                }
                ProcessEvent(eventType, delayUs, data);
            }
            return true;
        }

        // Applies one host event. Returns true if it was a park (ALARM_FIRED), which sets the deadline.
        private bool ProcessEvent(byte eventType, ulong delayUs, byte[] data)
        {
            switch(eventType)
            {
            case OtSimEventRadioSpinelWrite:
                Dbg($"RX WRITE len={data?.Length ?? 0} {Hex(data)}");
                InjectToRcp(data);
                return false;
            case OtSimEventAlarmFired:
                pendingDelay = TimeInterval.FromMicroseconds(delayUs);
                // Deadline is relative to where the host's clock is now (hostNow); this also avoids
                // firing a spurious alarm for a park that arrives after we have already advanced.
                deadline = hostNow + pendingDelay;
                Dbg($"RX PARK delay={delayUs}us");
                return true;
            default:
                this.Log(LogLevel.Warning, "VirtualTimePosixHost node {0}: unexpected event type {1}", nodeId, eventType);
                return false;
            }
        }

        private bool ReceiveEvent(out byte eventType, out ulong delayUs, out byte[] data)
        {
            eventType = 0;
            delayUs = 0;
            data = null;
            try
            {
                var received = socket.Receive(rxBuffer);
                if(received < HeaderSize)
                {
                    this.Log(LogLevel.Warning, "VirtualTimePosixHost node {0}: short packet ({1} bytes)", nodeId, received);
                    return true; // treat as a no-op event, keep going
                }
                delayUs = BitConverter.ToUInt64(rxBuffer, 0);
                eventType = rxBuffer[8];
                var dataLength = BitConverter.ToUInt16(rxBuffer, 9);
                dataLength = (ushort)Math.Min(dataLength, received - HeaderSize);
                data = new byte[dataLength];
                Array.Copy(rxBuffer, HeaderSize, data, 0, dataLength);
                return true;
            }
            catch(Exception e) when(e is SocketException || e is ObjectDisposedException)
            {
                return false;
            }
        }

        private void SendSpinelToHost(byte[] frame)
        {
            Dbg($"TX SPINEL len={frame.Length} mDelay={(hostNow - lastDelivered).TotalMicroseconds:F0}us");
            SendEvent(OtSimEventRadioSpinelWrite, frame);
            lastDelivered = hostNow;
        }

        private void SendAlarmToHost()
        {
            Dbg($"TX ALARM mDelay={(hostNow - lastDelivered).TotalMicroseconds:F0}us");
            SendEvent(OtSimEventAlarmFired, null);
            lastDelivered = hostNow;
        }

        private void SendEvent(byte eventType, byte[] data)
        {
            var dataLength = data?.Length ?? 0;
            var delayUs = (hostNow - lastDelivered).Ticks / TimeInterval.TicksPerMicrosecond;

            var packet = new byte[HeaderSize + dataLength];
            var delayBytes = BitConverter.GetBytes(delayUs);
            Array.Copy(delayBytes, 0, packet, 0, 8);
            packet[8] = eventType;
            var lenBytes = BitConverter.GetBytes((ushort)dataLength);
            Array.Copy(lenBytes, 0, packet, 9, 2);
            if(dataLength > 0)
            {
                Array.Copy(data, 0, packet, HeaderSize, dataLength);
            }

            try
            {
                socket.SendTo(packet, hostEndPoint);
            }
            catch(Exception e) when(e is SocketException || e is ObjectDisposedException)
            {
                if(!disposed)
                {
                    this.Log(LogLevel.Warning, "VirtualTimePosixHost node {0}: send failed: {1}", nodeId, e.Message);
                }
            }
        }

        // Feed the host's HDLC-encoded frame into the RCP UART RX through BackendTerminal's
        // flow-controlled buffer. CallCharReceived enqueues each byte; BackendTerminal drains it into
        // uart.WriteChar only while the RX buffer has room, resuming on BufferStateChanged. This paces
        // delivery to the emulated USART's 3-byte RX FIFO instead of overflowing it.
        private void InjectToRcp(byte[] data)
        {
            if(data == null)
            {
                return;
            }
            foreach(var b in data)
            {
                CallCharReceived(b);
            }
        }

        private TimeHandle handle;
        private Thread dispatcherThread;
        private volatile bool disposed;

        // Dispatcher-thread-only virtual-time bookkeeping.
        private TimeInterval hostNow;
        private TimeInterval lastDelivered;
        private TimeInterval deadline;
        private TimeInterval pendingDelay;

        private bool coalesceHasContent;

        private readonly int nodeId;
        private readonly Socket socket;
        private readonly IPEndPoint hostEndPoint;
        private readonly ConcurrentQueue<byte[]> rcpFrames;
        private readonly List<byte> coalesceBuffer;
        private readonly byte[] rxBuffer = new byte[HeaderSize + KMaxEventDataSize];

        // Wire protocol (openthread/src/posix/platform/platform-posix.h, virtual_time.cpp).
        // Flip to true to trace every event to /tmp/vthost_<nodeId>.log (debugging only).
        private static readonly bool DebugToFile = false;
        private const int HeaderSize = 11; // packed: uint64 mDelay, uint8 mEvent, uint16 mDataLength
        private const int KMaxEventDataSize = 1024;
        private const byte OtSimEventAlarmFired = 0;
        private const byte OtSimEventRadioSpinelWrite = 3;
        private const byte HdlcFlag = 0x7e;

        private const int KRcpBasePort = 9000;
        private const int KBasePort = 18000;
        private const int KMaxNetworkSize = 33;
    }
}
