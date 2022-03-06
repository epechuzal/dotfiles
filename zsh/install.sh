ZSH_THEME_DIR=~/powerlevel10k
if [ ! -d "$ZSH_THEME_DIR" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_THEME_DIR"
fi
