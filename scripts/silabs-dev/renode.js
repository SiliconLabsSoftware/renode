const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const rootDir = path.join(__dirname, '..', '..')
const testLibDir = path.join(rootDir, 'tests', 'test_lib')

const crossCompileDotNet = 'net8.0'

function renodeVersion() {
  const out = execFileSync(path.join(rootDir, 'renode'), ['--version'], {
    cwd: rootDir,
    encoding: 'utf8',
  })
  const result = {}
  const lines = out.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) {
      continue
    }
    if (i === 0 && !line.includes(':')) {
      const m = line.match(/^(\S+)\s+v(.+)$/)
      if (m) {
        result.name = m[1]
        result.version = m[2]
      } else {
        result.banner = line
      }
      continue
    }
    const colon = line.indexOf(':')
    if (colon === -1) {
      continue
    }
    const key = line.slice(0, colon).trim()
    const value = line.slice(colon + 1).trim()
    result[key] = value
  }
  return result
}

function silabsVersion() {
  const silabsPath = path.join(rootDir, 'SILABS-VERSION')
  const silabsVer = fs.readFileSync(silabsPath, 'utf8').trim()
  if (!silabsVer) {
    throw new Error('SILABS-VERSION is empty')
  }
  return silabsVer
}

function silabsRenodeVersion() {
  const silabsVer = silabsVersion()
  const info = renodeVersion()
  const ver = info.version
  if (!ver) {
    throw new Error(
      'renode --version output did not include a parseable version',
    )
  }
  return `${silabsVer}+v${ver}`
}

function fetchLibraries() {
  console.log('🔨 Fetching libraries...')
  execFileSync('bash', ['tools/building/fetch_libraries.sh'], {
    cwd: rootDir,
    stdio: 'inherit',
  })
}

function buildRenode() {
  console.log('🔨 Building Renode from source...')
  fetchLibraries()
  const env = {
    ...process.env,
    OPENSSL_ENABLE_SHA1_SIGNATURES: '1',
  }
  execFileSync(path.join(rootDir, 'build.sh'), ['--skip-fetch', '--net'], {
    cwd: rootDir,
    stdio: 'inherit',
    env,
  })

  if (process.platform === 'linux') {
    const releaseDir = path.join(rootDir, 'output', 'bin', 'Release')
    const softlink = path.join(releaseDir, 'libMono.Unix.so')
    if (!fs.existsSync(softlink)) {
      execFileSync(
        'ln',
        ['-s', 'runtimes/linux-x64/native/libMono.Unix.so', '.'],
        {
          cwd: releaseDir,
          stdio: 'inherit',
        },
      )
    }
  }
}

function cleanRenode() {
  console.log('🧹 Cleaning Renode build...')
  execFileSync(path.join(rootDir, 'build.sh'), ['-c'], {
    cwd: rootDir,
    stdio: 'inherit',
  })
}

function buildWinRenode() {
  console.log('🪟 Building Renode for Windows...')
  const env = {
    ...process.env,
    CC: 'x86_64-w64-mingw32-gcc',
  }
  execFileSync(path.join(rootDir, 'build.sh'), ['-c'], {
    cwd: rootDir,
    stdio: 'inherit',
    env,
  })
  execFileSync(
    'dotnet',
    [
      'publish',
      'src/Renode/Renode.csproj',
      '-c',
      'Release',
      '-r',
      'win-x64',
      '--self-contained',
      '-f',
      crossCompileDotNet,
    ],
    {
      cwd: rootDir,
      stdio: 'inherit',
      env,
    },
  )
}

function buildMacRenode() {
  console.log('🍎 Building Renode for macOS...')
  execFileSync(
    'dotnet',
    [
      'publish',
      'src/Renode/Renode.csproj',
      '-c',
      'Release',
      '-r',
      'osx-x64',
      '--self-contained',
      '-f',
      crossCompileDotNet,
    ],
    {
      cwd: rootDir,
      stdio: 'inherit',
    },
  )
}

function buildHostLibrary() {
  console.log('🔨 Building host library...')
  const buildDir = path.join(rootDir, 'build')
  fs.mkdirSync(buildDir, { recursive: true })
  const libDir = path.join(rootDir, 'tools', 'external_control_client', 'lib')
  execFileSync('cmake', ['-DCMAKE_BUILD_SHARED_LIBS=ON', libDir], {
    cwd: buildDir,
    stdio: 'inherit',
  })
  execFileSync('make', [], {
    cwd: buildDir,
    stdio: 'inherit',
  })
}

function testingSetUp() {
  const pipOpts = { cwd: rootDir, stdio: 'inherit' }
  console.log('   ✳️ Upgrade pip')
  execFileSync('pip3', ['install', '--upgrade', 'pip'], pipOpts)
  console.log('   ✳️ Standard renode requirements.')
  execFileSync('pip3', ['install', '-r', 'tests/requirements.txt'], pipOpts)
  console.log('   ✳️ Pyrenode3 package for testing.')
  execFileSync(
    'pip3',
    [
      'install',
      'pyrenode3[all] @ git+https://github.com/antmicro/pyrenode3.git',
    ],
    pipOpts,
  )
  console.log('   ✳️ SiLabs test_lib package.')
  execFileSync('pip3', ['install', '-e', testLibDir], pipOpts)
  console.log('   ✳️ Verify test_lib pip installation.')
  execFileSync('pip3', ['show', 'test_lib'], pipOpts)
  console.log('   ✳️ bgapi package.')
  execFileSync('pip3', ['install', 'pybgapi==1.3.*'], pipOpts)
}

exports.buildHostLibrary = buildHostLibrary
exports.buildRenode = buildRenode
exports.buildMacRenode = buildMacRenode
exports.buildWinRenode = buildWinRenode
exports.cleanRenode = cleanRenode
exports.fetchLibraries = fetchLibraries
exports.testingSetUp = testingSetUp
exports.renodeVersion = renodeVersion
exports.silabsRenodeVersion = silabsRenodeVersion
exports.silabsVersion = silabsVersion
