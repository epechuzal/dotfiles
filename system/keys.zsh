# Pipe my public key to my clipboard.
if [[ "$(uname -s)" == "Darwin" ]]; then
  alias pubkey="more ~/.ssh/id_rsa.pub | pbcopy | echo '=> Public key copied to pasteboard.'"
elif (( $+commands[xclip] )); then
  alias pubkey="xclip -selection clipboard < ~/.ssh/id_rsa.pub && echo '=> Public key copied to clipboard.'"
elif (( $+commands[xsel] )); then
  alias pubkey="xsel --clipboard < ~/.ssh/id_rsa.pub && echo '=> Public key copied to clipboard.'"
fi
