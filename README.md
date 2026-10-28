# swapdog 🐶

*A good boy that watches your Mac's memory so you don't have to.*

You know who you are. 47 Chrome tabs, three half-written documents, a terminal with something running that you're "definitely getting back to", and an uptime measured in lunar cycles. You haven't restarted since the last OS update forced you to, and you resent it.

Your Mac has been quietly filling up its swap file. First the spinning beach ball drops by for a visit. Then it moves in. Then one day macOS informs you that *your system has run out of application memory* and asks which app you'd like to sacrifice.

swapdog keeps an eye on it. When things have been bad for long enough, it barks. Once a day, tops. It's a good dog, not an annoying one.

## What it sniffs

Every 10 minutes, swapdog checks:

- **Swap usage**: above **6 GB** is suspicious.
- **Memory pressure**: *warning* or *critical* is suspicious, whatever the swap says.

While either one is suspicious, it adds 10 minutes to its counter. Once the counter reaches **4 hours**, a dog shows up in the middle of your screen asking you to save your stuff and restart. You can say **Later** (it'll be back tomorrow) or **Restart now** (it'll be so proud of you).

It only counts time your Mac is awake, so working in 20-minute bursts still adds up (nice try).

The counter goes back to zero when:

- you restart (good human 🦴), or
- swap drops below **5 GB** with normal pressure. The 1 GB gap stops it from flip-flopping around the threshold.

## Install

```sh
git clone https://github.com/tlifschitz/swapdog.git
cd swapdog
./install.sh
```

That puts the script in `~/.local/bin/swapdog`, its face in `~/.local/share/swapdog/`, its notes in `~/.local/state/swapdog/` and a LaunchAgent in `~/Library/LaunchAgents/`.

The first time you click **Restart now**, macOS asks whether swapdog may control **System Events**. Say yes: that's how it politely asks your Mac to restart, giving your apps a chance to save your work.

### Check what it's thinking

```sh
cat ~/.local/state/swapdog/state
```

`acc` is how many seconds of suspicious behavior it has seen so far.

## Uninstall

```sh
./uninstall.sh
```

Then restart. Not for swapdog, it's gone. For you.

## Tweaking

The thresholds live at the top of `swapdog.sh`. 6 GB made sense on a 16 GB Mac; adjust to taste and run `./install.sh` again.

## Tests

```sh
bash tests/run_tests.sh
```

`sysctl`, `date` and `osascript` are faked, so the tests don't care how many tabs you have open right now. They also run on every push in CI on macOS.

## Credits

The dog is 🐶 from [Noto Emoji](https://github.com/googlefonts/noto-emoji) by Google, used under the [SIL Open Font License 1.1](LICENSE-noto-emoji). Everything else is [MIT](LICENSE).
