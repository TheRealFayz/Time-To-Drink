Time To Drink - Turtle WoW (vanilla 1.12) addon  v1.0
=====================================================

WHAT IT DOES
  In a 5-man party (disabled in raids) it watches a healer you pick and posts
  to PARTY chat when their mana drops below your threshold, repeating on a
  cooldown you set (minimum 10s). Message: "<Healer> has less than <X>% mana".

INSTALL
  Copy the "TimeToDrink" folder into <Turtle WoW>\Interface\AddOns\ so you have:
     ...\Interface\AddOns\TimeToDrink\TimeToDrink.toc
     ...\Interface\AddOns\TimeToDrink\TimeToDrink.lua
  IMPORTANT: make sure it is NOT double-nested (no TimeToDrink\TimeToDrink\...).
  Then /reload or restart, and tick it in the AddOns list at character select.

COMMANDS
  /ttd          open / close the window
  /ttd status   print current threshold, cooldown, healer, and party state
  /ttd test     send a test line to party chat (only works while in a party)
  /ttd debug    toggle verbose messages (announces show up in your own chat)

TROUBLESHOOTING
  Turn on Lua errors so problems are visible:  /console scriptErrors 1
  This build also prints any error to your chat in red starting "TTD error:".
