# Named terminal colours

Source: X.Org rgb 1.1.1, https://xorg.freedesktop.org/archive/individual/app/rgb-1.1.1.tar.gz
Archive SHA256: 9bceca0821a46ff54989ab08ab00d6dd87eb2779fc15165d848eaa0ddd742fbe
Original rgb.txt SHA256: f8e3a7bea17acc0b91e6285c5d32001db27d84c4461c655afdbce9dbeb4fb6f0

The accompanying color-names.LICENSE is the unmodified upstream COPYING.
The normalized table is sorted by lower-case ASCII name and consists of
six lower-case hex digits, one ASCII space, the complete name and LF.
Original spaced and unspaced aliases remain distinct. No runtime X11
database or package is required. The DebianRed alias is the independently
documented RGB fact (215,7,81) from the Debian X11 colour database:
https://lists.debian.org/debian-x/2004/04/msg00568.html
The selected value also appears in distributed rgb.txt copies and matches
the pinned Kitty vocabulary. This is a factual colour mapping, not logo
artwork or borrowed implementation.

To regenerate with Python 3, read upstream rgb.txt as ASCII; skip blank
and comment lines; split each row at its first three whitespace-delimited
fields, convert those channels to integers, lowercase the remaining
name, and reject conflicting duplicate names. Add the DebianRed alias,
sort by name, and serialize each row as six hex digits, space, name, LF.
There are 783 unique case-insensitive names: all 782 upstream names plus
DebianRed. A read-only comparison with pinned Kitty a79f376 found all
753 of its names have identical RGB values, with 30 additional upstream
X.Org aliases. No Kitty implementation or table was copied.
