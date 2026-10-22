#!/bin/bash
# Build Ruby and its native dependencies from source into ~/local (macOS).

set -euo pipefail

# ---- Versions ---------------------------------------------------------------
RUBY_VERSION="4.0.8"
OPENSSL_VERSION="3.5.8"     # 3.5 is the LTS series; 3.5.0 has known CVEs
ZLIB_VERSION="1.3.1"
YAML_VERSION="0.2.5"

PREFIX="$HOME/local"
RUBY_PREFIX="$PREFIX/ruby-${RUBY_VERSION}"
RUBY_SERIES="${RUBY_VERSION%.*}"   # 4.0.8 -> 4.0 (used in the download path)
NUM_CORES=$(sysctl -n hw.ncpu)

mkdir -p "$PREFIX/src"
cd "$PREFIX/src"

# ---- Xcode Command Line Tools ----------------------------------------------
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install || true
  echo "Rerun this script once the installer finishes."
  exit 1
fi

# ---- Helpers ----------------------------------------------------------------
# Download (failing loudly on HTTP errors instead of saving an error page),
# reuse a previous download if it's a valid archive, then extract.
fetch() {
  local url=$1
  local file=${url##*/}
  if [[ -f "$file" ]] && ! tar -tzf "$file" &>/dev/null; then
    echo "==> Discarding invalid cached $file"
    rm -f "$file"
  fi
  if [[ ! -f "$file" ]]; then
    echo "==> Downloading $file"
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  tar -xzf "$file"
}

# Standard ./configure && make && make install, run in a subshell so the
# working directory is always restored.
build_autotools() {
  local url=$1 dir=$2
  shift 2
  echo "==> Building $dir"
  fetch "$url"
  (
    cd "$dir"
    ./configure --prefix="$PREFIX" "$@"
    make -j"$NUM_CORES"
    make install
  )
}

# ---- Dependencies -----------------------------------------------------------
# zlib: GitHub release URLs are permanent; zlib.net drops old versions.
build_autotools \
  "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" \
  "zlib-${ZLIB_VERSION}"

# OpenSSL uses its own Configure script, not autotools.
echo "==> Building openssl-${OPENSSL_VERSION}"
fetch "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
(
  cd "openssl-${OPENSSL_VERSION}"
  ./Configure "darwin64-$(uname -m)-cc" \
    --prefix="$PREFIX" \
    --openssldir="$PREFIX/ssl"
  make -j"$NUM_CORES"
  make install_sw install_ssldirs   # skip the slow man/html doc install
)

# A source-built OpenSSL ships with no CA certificates, so HTTPS (including
# `gem install`) fails with "certificate verify failed". Point it at the
# bundle macOS maintains.
if [[ -f /etc/ssl/cert.pem ]]; then
  ln -sf /etc/ssl/cert.pem "$PREFIX/ssl/cert.pem"
else
  echo "WARNING: /etc/ssl/cert.pem not found; put a CA bundle at $PREFIX/ssl/cert.pem" >&2
fi

# libyaml: required by psych (Ruby no longer bundles it).
build_autotools \
  "https://pyyaml.org/download/libyaml/yaml-${YAML_VERSION}.tar.gz" \
  "yaml-${YAML_VERSION}"

# GNU readline is intentionally not built: Ruby 3.3+ removed the readline
# extension and uses the pure-Ruby reline instead.

# ---- Ruby -------------------------------------------------------------------
echo "==> Building ruby-${RUBY_VERSION}"
fetch "https://cache.ruby-lang.org/pub/ruby/${RUBY_SERIES}/ruby-${RUBY_VERSION}.tar.gz"
(
  cd "ruby-${RUBY_VERSION}"
  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-L$PREFIX/lib"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

  ./configure --prefix="$RUBY_PREFIX" \
    --with-openssl-dir="$PREFIX" \
    --with-zlib-dir="$PREFIX" \
    --with-libyaml-dir="$PREFIX" \
    --disable-install-doc

  make -j"$NUM_CORES"
  # make test
  make install
)

# ---- Verify -----------------------------------------------------------------
# Ruby's build only warns when an extension fails to compile, so check the
# important ones actually load and that TLS certificate verification works.
echo "==> Verifying"
"$RUBY_PREFIX/bin/ruby" -ropenssl -rpsych -rzlib -rnet/http -e '
  puts RUBY_DESCRIPTION
  puts OpenSSL::OPENSSL_LIBRARY_VERSION
  Net::HTTP.get_response(URI("https://rubygems.org"))
  puts "HTTPS OK"
'

# ---- PATH -------------------------------------------------------------------
case "$SHELL" in
  */zsh) SHELL_RC="$HOME/.zshrc" ;;
  *)     SHELL_RC="$HOME/.bash_profile" ;;
esac
touch "$SHELL_RC"

if ! grep -qF "$RUBY_PREFIX/bin" "$SHELL_RC"; then
  # shellcheck disable=SC2016  # $PATH is meant to stay literal in the rc file
  printf '\nexport PATH="%s:$PATH"\n' "$RUBY_PREFIX/bin" >> "$SHELL_RC"
  echo "Added $RUBY_PREFIX/bin to PATH in $SHELL_RC"
else
  echo "$RUBY_PREFIX/bin is already in $SHELL_RC"
fi

echo "Done. Open a new terminal (or run: source $SHELL_RC), then check with: ruby -v"