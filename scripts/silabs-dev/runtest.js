// This script is used to run test suites defined in tests/silabs_tests.json. It can be invoked with a specific suite name or with the --matrix flag to output a JSON configuration for GitHub Actions matrix strategy.

const fs = require('fs')
const path = require('path')
const os = require('os')
const { execFileSync } = require('child_process')
const renode = require('./renode')

const FIRMWARE_RELEASE = 'firmware-dev'
const DEFAULT_FIRMWARE_BASE_URL =
  'https://github.com/SiliconLabsSoftware/renode/releases/download/firmware-dev'
const repoRoot = path.join(__dirname, '..', '..')

// Downloads a private release asset via the GitHub API. The token is sent only
// to the API host; the redirect to the asset CDN goes out without it.
const DOWNLOAD_ASSET = `
const fs = require('fs')
const http = require('http')
const https = require('https')
const target = process.argv[1]
const dest = process.argv[2]
const token = process.env.RENODE_ASSET_TOKEN || ''
const apiBase = (process.env.GITHUB_API_URL || 'https://api.github.com').replace(/\\/$/, '')
function request(url, headers, left) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https:') ? https : http
    const req = lib.get(url, { headers }, (res) => {
      const code = res.statusCode || 0
      if (code >= 300 && code < 400 && res.headers.location) {
        res.resume()
        if (left <= 0) { reject(new Error('Too many redirects for ' + url)); return }
        const next = new URL(res.headers.location, url).href
        const nextHeaders = Object.assign({}, headers)
        if (new URL(next).host !== new URL(url).host) delete nextHeaders.Authorization
        resolve(request(next, nextHeaders, left - 1))
        return
      }
      const chunks = []
      res.on('data', (chunk) => chunks.push(chunk))
      res.on('end', () => resolve({ code, body: Buffer.concat(chunks) }))
    })
    req.on('error', reject)
  })
}
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
// Release asset storage intermittently returns 5xx for an object that exists.
const TRANSIENT_HTTP = { 500: true, 502: true, 503: true, 504: true }
async function requestWithRetry(url, headers, what) {
  const attempts = 4
  let lastError
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const res = await request(url, headers, 5)
      if (res.code === 200 || !TRANSIENT_HTTP[res.code]) return res
      lastError = new Error('HTTP ' + res.code + ' ' + what)
    } catch (err) {
      lastError = err
    }
    if (attempt === attempts) break
    const waitMs = 2000 * Math.pow(2, attempt - 1)
    console.error(lastError.message + '; retrying in ' + (waitMs / 1000) + 's')
    await sleep(waitMs)
  }
  throw lastError
}
async function main() {
  const parts = new URL(target).pathname.split('/').filter(Boolean)
  if (parts.length < 6 || parts[2] !== 'releases' || parts[3] !== 'download') {
    throw new Error('Not a GitHub release asset URL: ' + target)
  }
  const owner = parts[0]
  const repo = parts[1]
  const tag = decodeURIComponent(parts[4])
  const name = decodeURIComponent(parts.slice(5).join('/'))
  const auth = {
    'User-Agent': 'renode-runtest',
    Authorization: 'Bearer ' + token,
    'X-GitHub-Api-Version': '2022-11-28',
  }
  const releaseUrl = apiBase + '/repos/' + owner + '/' + repo + '/releases/tags/' + encodeURIComponent(tag)
  const release = await requestWithRetry(releaseUrl, Object.assign({ Accept: 'application/vnd.github+json' }, auth), 'reading release ' + tag + ' from ' + owner + '/' + repo)
  if (release.code !== 200) {
    throw new Error('HTTP ' + release.code + ' reading release ' + tag + ' from ' + owner + '/' + repo)
  }
  const asset = (JSON.parse(release.body.toString('utf8')).assets || []).find((item) => item.name === name)
  if (!asset) throw new Error('Release ' + tag + ' on ' + owner + '/' + repo + ' has no asset ' + name)
  const file = await requestWithRetry(asset.url, Object.assign({ Accept: 'application/octet-stream' }, auth), 'downloading asset ' + name)
  if (file.code !== 200) throw new Error('HTTP ' + file.code + ' downloading asset ' + name)
  fs.writeFileSync(dest, file.body, { mode: 0o755 })
}
main().catch((err) => { console.error(err.message); process.exit(1) })
`

let cachedFirmwareBaseUrl
const assetCache = new Map()
const downloadedAssets = []

process.on('exit', () => {
  for (let file of downloadedAssets) {
    try {
      fs.unlinkSync(file)
    } catch {
      // The workflow also removes /tmp/renode_* after a killed job.
    }
  }
})

let tests = require('../../tests/silabs_tests.json')

const SILABS_UNIT_TEST_PREFIX = 'unit-test-'

function availableSuiteNames() {
  return Object.keys(tests)
}

/** Leaf JSON keys, or every `unit-test-*` suite when the name is the `silabs` alias. */
function resolveSuiteNames(suiteName) {
  if (suiteName in tests) {
    return [suiteName]
  }
  if (suiteName === 'silabs') {
    return availableSuiteNames().filter((name) =>
      name.startsWith(SILABS_UNIT_TEST_PREFIX),
    )
  }
  return []
}

function printAvailableSuites() {
  console.error(
    'Available suites:',
    [...availableSuiteNames(), 'silabs'].join(', '),
  )
}

/** Prefer the venv from `./r testing-set-up` when it exists. */
function pythonExecutable() {
  let candidate = renode.venvPython()
  return fs.existsSync(candidate) ? candidate : 'python3'
}

/**
 * Turn `git@host:owner/repo.git`, `ssh://git@host/owner/repo.git`, or an
 * https remote into `{ server, repo }`. server is always an https origin.
 */
function parseGitRemote(url) {
  let remote = String(url).trim()
  let match = remote.match(
    /^https?:\/\/([^/]+)\/([^/]+\/[^/]+?)(?:\.git)?\/?$/,
  )
  if (match) {
    return { server: `https://${match[1]}`, repo: match[2] }
  }
  match = remote.match(
    /^ssh:\/\/(?:[^@/]+@)?([^/]+)\/([^/]+\/[^/]+?)(?:\.git)?\/?$/,
  )
  if (match) {
    return { server: `https://${match[1]}`, repo: match[2] }
  }
  match = remote.match(/^(?:[^@/]+@)?([^:/]+):([^/]+\/[^/]+?)(?:\.git)?$/)
  if (match) {
    return { server: `https://${match[1]}`, repo: match[2] }
  }
  return null
}

function firmwareBaseFromRepo(server, repo) {
  return `${server.replace(/\/$/, '')}/${repo}/releases/download/${FIRMWARE_RELEASE}`
}

function firmwareBaseFromOrigin() {
  let url
  try {
    url = execFileSync('git', ['remote', 'get-url', 'origin'], {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    return null
  }
  let parsed = parseGitRemote(url)
  if (!parsed) {
    return null
  }
  return firmwareBaseFromRepo(parsed.server, parsed.repo)
}

/**
 * Base URL of the firmware-dev release for this run.
 *
 * 1. RENODE_FIRMWARE_BASE_URL, when set.
 * 2. The repo the workflow is running in (GITHUB_SERVER_URL + GITHUB_REPOSITORY).
 *    That is https://github.com/SiliconLabsSoftware/renode on the public repo and
 *    https://github.com/SiliconLabsInternal/renode on the internal one.
 * 3. The same shape derived from `git remote get-url origin`.
 * 4. The public SiliconLabsSoftware release.
 */
function firmwareBaseUrl() {
  if (cachedFirmwareBaseUrl) {
    return cachedFirmwareBaseUrl
  }
  let override = process.env.RENODE_FIRMWARE_BASE_URL
  if (override) {
    cachedFirmwareBaseUrl = override.replace(/\/$/, '')
    return cachedFirmwareBaseUrl
  }
  let server = process.env.GITHUB_SERVER_URL
  let repo = process.env.GITHUB_REPOSITORY
  if (server && repo) {
    cachedFirmwareBaseUrl = firmwareBaseFromRepo(server, repo)
    return cachedFirmwareBaseUrl
  }
  cachedFirmwareBaseUrl = firmwareBaseFromOrigin() || DEFAULT_FIRMWARE_BASE_URL
  return cachedFirmwareBaseUrl
}

/**
 * Expand a bare firmware-dev asset name to a release URL.
 * Full URLs and filesystem paths are returned unchanged.
 */
function resolveFirmwareRef(value, base = firmwareBaseUrl()) {
  if (typeof value !== 'string' || value === '') {
    return value
  }
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
    return value
  }
  if (
    value.startsWith('/') ||
    value.startsWith('./') ||
    value.startsWith('../') ||
    value.includes('/') ||
    value.includes('\\')
  ) {
    return value
  }
  return `${base.replace(/\/$/, '')}/${value}`
}

/**
 * Download a release asset when this run has a GitHub token, and return the
 * local path. Public anonymous URLs are returned unchanged so Renode and
 * test_lib fetch them as before.
 *
 * GITHUB_TOKEN is not a default Actions environment variable; the test step
 * passes it in. A private release answers 404 without it, including to
 * Renode's own downloader, so robot suites need the file on disk too.
 */
function materializeReleaseAsset(url) {
  if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) {
    return url
  }
  let token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN
  if (!token) {
    return url
  }
  // Only attach the token to the host that serves this run's firmware release.
  // Redirects (the asset CDN) are fetched without it.
  let firmwareHost
  try {
    firmwareHost = new URL(firmwareBaseUrl()).host
    if (new URL(url).host !== firmwareHost) {
      return url
    }
  } catch {
    return url
  }
  if (assetCache.has(url)) {
    return assetCache.get(url)
  }
  let filename = url.split('/').pop() || 'binary'
  let dest = path.join(
    os.tmpdir(),
    `renode_${filename}_${process.pid}_${assetCache.size}`,
  )
  execFileSync(process.execPath, ['-e', DOWNLOAD_ASSET, url, dest], {
    env: {
      ...process.env,
      RENODE_ASSET_TOKEN: token,
      RENODE_ASSET_SERVER_HOST: firmwareHost,
    },
    stdio: 'inherit',
  })
  fs.chmodSync(dest, 0o755)
  assetCache.set(url, dest)
  downloadedAssets.push(dest)
  return dest
}

/**
 * Firmware params: expand asset names, then fetch private assets.
 * ELF / ELF2 / ... are the usual robot and test_lib binaries.
 * BIN_* covers secure_engine.py (BIN_HOST, BIN_SE, BIN_ROM, BIN_OTP, BIN_MTP),
 * which loads each file with Renode's LoadELF / LoadBinary and does not
 * download on its own.
 */
function isFirmwareParam(key) {
  return /^ELF\d*$/.test(key) || /^BIN_/.test(key)
}

function resolveSuiteParams(params) {
  let resolved = {}
  for (let [key, value] of Object.entries(params)) {
    if (isFirmwareParam(key)) {
      let url = resolveFirmwareRef(value)
      let local = materializeReleaseAsset(url)
      resolved[key] = local
      if (local !== url) {
        console.log(`    ${key}: ${url}`)
        console.log(`      -> ${local}`)
      } else {
        console.log(`    ${key}: ${url}`)
      }
    } else {
      resolved[key] = value
      console.log(`    ${key}: ${value}`)
    }
  }
  return resolved
}

/** Put the test venv on PATH so renode-test's python3 sees installed packages. */
function withVenv(env) {
  let binDir = renode.venvBinDir()
  if (!fs.existsSync(binDir)) {
    return env
  }
  return {
    ...env,
    VIRTUAL_ENV: renode.venvDir(),
    PATH: `${binDir}${path.delimiter}${env.PATH || ''}`,
  }
}

/** Quote one argv token for safe copy-paste into a POSIX shell. */
function shellQuote(arg) {
  let s = String(arg)
  if (s === '') {
    return "''"
  }
  if (/^[\w@%+=:,./-]+$/.test(s)) {
    return s
  }
  return `'${s.replace(/'/g, `'\\''`)}'`
}

/** Log the exact program + argv, plus env assignments this script adds for the child. */
function logInvokedCommand(program, argv, envAssignments) {
  let envPrefix = Object.entries(envAssignments)
    .filter(([, v]) => v != null && v !== '')
    .map(([k, v]) => `${k}=${shellQuote(v)}`)
    .join(' ')
  let tokens = [program, ...argv].map(shellQuote).join(' ')
  if (envPrefix) {
    console.log(`  ↳ Command: ${envPrefix} ${tokens}`)
  } else {
    console.log(`  ↳ Command: ${tokens}`)
  }
}

// The main function that runs a test suite based on the provided suite name.
function runTest(suiteName) {
  // You must pass in something.
  if (!suiteName) {
    console.error('Usage: ./r runtest [ --matrix | <suite-name> ]')
    printAvailableSuites()
    process.exit(1)
  }

  // If you pass the argument --matrix, the script will output a JSON configuration for GitHub Actions matrix strategy and exit.
  if (suiteName === '--matrix') {
    let testSuites = Object.keys(tests)
    let matrix = {
      include: testSuites.map((suite) => ({ test: suite })),
    }
    console.log(`matrix-config=${JSON.stringify(matrix)}`)
    process.exit(0)
  }

  let suiteNames = resolveSuiteNames(suiteName)
  if (suiteNames.length === 0) {
    console.error(`Unknown suite: ${suiteName}`)
    printAvailableSuites()
    process.exit(1)
  }

  // Print hardware information once, including when `silabs` expands to several groups.
  let cpus = os.cpus()
  let numCpus = cpus.length
  let cpuModel = numCpus > 0 ? cpus[0].model : 'unknown'
  let cpuSpeedMhz = numCpus > 0 ? cpus[0].speed : 0
  let totalMemMB = Math.round(os.totalmem() / (1024 * 1024))
  let freeMemMB = Math.round(os.freemem() / (1024 * 1024))
  console.log(
    `  ↳ Hardware: ${os.platform()} ${os.arch()}, ${numCpus} CPU(s) @ ${cpuSpeedMhz} MHz`,
  )
  console.log(`  ↳ CPU model: ${cpuModel}`)
  console.log(`  ↳ Memory: ${freeMemMB} MB free / ${totalMemMB} MB total`)
  console.log(`  ↳ Hostname: ${os.hostname()}`)
  console.log(`  ↳ Firmware: ${firmwareBaseUrl()}`)

  for (let name of suiteNames) {
    runSuite(name)
  }
}

function runSuite(suiteName) {
  let suite = tests[suiteName].tests

  console.log(`🎁 Running test suite: ${tests[suiteName].title}`)

  let suiteStart = Date.now()

  for (let entry of suite) {
    let testPath

    if (typeof entry === 'string') {
      testPath = entry
    } else {
      testPath = entry.test
    }

    console.log(`🚀 Running test: ${testPath}`)
    let params =
      typeof entry === 'object' && entry.params
        ? resolveSuiteParams(entry.params)
        : null

    let isPython = testPath.endsWith('.py')
    let testStart = Date.now()

    try {
      if (isPython) {
        let args = [testPath]
        if (params) {
          for (let [key, value] of Object.entries(params)) {
            args.push(`--${key.toLowerCase()}`, value)
          }
        }
        let rootDir = path.join(__dirname, '..', '..')

        let theEnv = { ...process.env, PYRENODE_BUILD_DIR: rootDir }
        if (process.env.RENODE_PORTABLE_LOCATION) {
          let renodeFile = path.join(
            __dirname,
            '..',
            '..',
            process.env.RENODE_PORTABLE_LOCATION,
            'renode',
          )
          theEnv = {
            ...process.env,
            PYRENODE_BIN: renodeFile,
          }
        }
        theEnv = withVenv(theEnv)
        let python = pythonExecutable()
        let pythonEnvLog = process.env.RENODE_PORTABLE_LOCATION
          ? { PYRENODE_BIN: theEnv.PYRENODE_BIN }
          : { PYRENODE_BUILD_DIR: rootDir }
        logInvokedCommand(python, args, pythonEnvLog)
        execFileSync(python, args, {
          stdio: 'inherit',
          env: theEnv,
        })
      } else {
        let testRunner = path.join(__dirname, '..', '..', 'renode-test')

        if (process.env.RENODE_PORTABLE_LOCATION) {
          testRunner = path.join(
            __dirname,
            '..',
            '..',
            process.env.RENODE_PORTABLE_LOCATION,
            'renode-test',
          )
        }

        let args = []
        if (params) {
          for (let [key, value] of Object.entries(params)) {
            args.push('--variable', `${key}:${value}`)
          }
        }
        args.push(testPath)
        let robotEnv = withVenv(process.env)
        logInvokedCommand(testRunner, args, {})
        execFileSync(testRunner, args, {
          stdio: 'inherit',
          env: robotEnv,
        })
      }
    } catch (err) {
      let elapsed = Date.now() - testStart
      console.error(`⛔ Test failed: ${testPath} (${elapsed} ms)`)
      process.exit(err.status || 1)
    }
    let elapsed = Date.now() - testStart
    console.log(`✅ Done: ${testPath} (${elapsed} ms)\n`)
  }

  let suiteElapsed = Date.now() - suiteStart
  console.log(
    `🏁 Suite "${tests[suiteName].title}" completed in ${suiteElapsed} ms`,
  )
}

exports.runTest = runTest
exports.parseGitRemote = parseGitRemote
exports.firmwareBaseUrl = firmwareBaseUrl
exports.resolveFirmwareRef = resolveFirmwareRef
exports.materializeReleaseAsset = materializeReleaseAsset
