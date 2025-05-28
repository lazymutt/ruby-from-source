#!/bin/bash

set -e

# Directory to install all libraries and Ruby
PREFIX="$HOME/local"
mkdir -p "$PREFIX/src"
cd "$PREFIX/src"

NUM_CORES=$(sysctl -n hw.ncpu)

# Install Xcode Command Line Tools if needed
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Please rerun the script after installation finishes."
    exit 1
fi

# Function to download, build, and install libraries
build_lib() {
  local url=$1
  local folder=$2
  local config_flags=$3

  echo "Building $folder..."
  curl -LO "$url"
  tar -xzf "${url##*/}"
  cd "$folder"
  ./configure --prefix="$PREFIX" $config_flags
  make -j"$NUM_CORES"
  make install
  cd ..
}

# Build dependencies
build_lib https://zlib.net/zlib-1.3.1.tar.gz zlib-1.3.1 ""

build_lib https://ftp.gnu.org/gnu/readline/readline-8.2.tar.gz readline-8.2 ""

build_lib https://github.com/openssl/openssl/releases/download/openssl-3.5.0/openssl-3.5.0.tar.gz openssl-3.5.0 \
  "darwin64-$(uname -m)-cc --openssldir=$PREFIX"

curl -LO https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz
tar -xzf yaml-0.2.5.tar.gz
cd yaml-0.2.5
./configure --prefix="$PREFIX"
make -j"$NUM_CORES"
make install
cd ..

# Build Ruby
RUBY_VERSION=3.4.4
curl -O "https://cache.ruby-lang.org/pub/ruby/3.4/ruby-${RUBY_VERSION}.tar.gz"
tar -xzf "ruby-${RUBY_VERSION}.tar.gz"
cd "ruby-${RUBY_VERSION}"

export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

./configure --prefix="$PREFIX/ruby-${RUBY_VERSION}" \
  --with-openssl-dir="$PREFIX" \
  --with-readline-dir="$PREFIX" \
  --with-zlib-dir="$PREFIX" \
  --with-libyaml-dir="$PREFIX"

make -j"$NUM_CORES"
# make test
make install

# Add Ruby to PATH
SHELL_RC="$HOME/.bash_profile"
if [[ $SHELL == *zsh ]]; then
  SHELL_RC="$HOME/.zshrc"
fi

if ! grep -q "ruby-${RUBY_VERSION}" "$SHELL_RC"; then
  echo 'export PATH="'$PREFIX'/ruby-'$RUBY_VERSION'/bin:$PATH"' >> "$SHELL_RC"
  echo "Ruby $RUBY_VERSION installed. Add this to your PATH:"
  echo "  export PATH=\"$PREFIX/ruby-${RUBY_VERSION}/bin:\$PATH\""
  echo "This has been added to $SHELL_RC. Restart your shell or run:"
  echo "  source $SHELL_RC"
else
  echo "Ruby path already in $SHELL_RC"
fi

echo "Done. Run 'ruby -v' to verify installation."
