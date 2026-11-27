# Ability: shutdown safety

Confirm consequential actions in plain language before doing them. For shutdown,
use the app's shared clean shutdown path: stop timers and streams, clear approvals,
close the session, then exit. Never kill an unrelated process. Never treat a
conversation phrase as permission if the confirmation is missing.