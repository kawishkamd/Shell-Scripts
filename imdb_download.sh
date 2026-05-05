#!/bin/bash

URL="$1"

if [ -z "$URL" ]; then
  echo "Usage: ./imdb_download.sh <imdb_or_playimdb_url>"
  exit 1
fi

echo "== Checking dependencies =="

# ---------- ffmpeg ----------
if ! command -v ffmpeg &> /dev/null; then
  echo "Installing ffmpeg..."
  sudo apt update && sudo apt install -y ffmpeg
else
  echo "ffmpeg already installed"
fi

# ---------- nvm ----------
export NVM_DIR="$HOME/.nvm"

if [ ! -d "$NVM_DIR" ]; then
  echo "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ---------- node ----------
if ! command -v node &> /dev/null || [[ $(node -v | cut -d. -f1 | tr -d 'v') -lt 18 ]]; then
  echo "Installing Node 18..."
  nvm install 18
  nvm use 18
  nvm alias default 18
else
  echo "Node OK: $(node -v)"
fi

# ---------- puppeteer ----------
if [ ! -d "node_modules/puppeteer" ]; then
  echo "Installing Puppeteer..."
  npm init -y >/dev/null 2>&1
  npm install puppeteer
else
  echo "Puppeteer already installed"
fi

# ---------- Convert IMDb → playIMDb ----------
if [[ "$URL" == *"imdb.com/title/"* ]]; then
  ID=$(echo "$URL" | grep -oE 'tt[0-9]+' | head -n 1)

  if [ -z "$ID" ]; then
    echo "Invalid IMDb URL"
    exit 1
  fi

  URL="https://www.playimdb.com/title/${ID}/"
  echo "Converted URL: $URL"
fi

# ---------- Create downloader.js ----------
cat << 'EOF' > downloader.js
const puppeteer = require('puppeteer');
const { spawn } = require('child_process');

const URL = process.argv[2];

(async () => {
  const browser = await puppeteer.launch({ headless: true });
  const page = await browser.newPage();

  let m3u8Url = null;

  page.on('response', async (response) => {
    const url = response.url();
    if (url.includes('.m3u8') && !m3u8Url) {
      m3u8Url = url;
      console.log("\n🎯 Found stream:\n", m3u8Url);
    }
  });

  await page.goto(URL, { waitUntil: 'networkidle2' });

  await new Promise(r => setTimeout(r, 10000));

  await browser.close();

  if (!m3u8Url) {
    console.log("❌ No m3u8 found.");
    process.exit(1);
  }

  console.log("\n⬇️ Downloading...\n");

  const ffmpeg = spawn('ffmpeg', [
    '-loglevel', 'warning',
    '-stats',
    '-i', m3u8Url,
    '-c', 'copy',
    'output.mp4'
  ]);

  ffmpeg.stdout.on('data', data => process.stdout.write(data));
  ffmpeg.stderr.on('data', data => process.stderr.write(data));

  ffmpeg.on('close', code => {
    if (code === 0) {
      console.log("\n✅ Download complete: output.mp4");
    } else {
      console.log("\n❌ Download failed");
    }
  });
})();
EOF

# ---------- Run ----------
echo "== Starting download =="
node downloader.js "$URL"
