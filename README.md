# about
csgo-like crouch stamina, the more you crouch the slower you do so<br>

almost guaranteed to not work with other movement addons because of how common it is for them to use https://wiki.facepunch.com/gmod/Player:SetDuckSpeed.<br>
please go ask for https://github.com/Facepunch/garrysmod-requests/issues/1403 to be resolved if you want this to improve.

# cvars
* ``sv_crouch_stamina`` - (``0/1``)
  * Sets whether crouch stamina is enabled or not.
* ``sv_crouch_stamina_cooldown`` - (``0 <--> float``)
  * Sets the minimum time players must wait before being allowed to crouch again.
* ``sv_crouch_stamina_spam_penalty`` - (``0 <--> float``)
  * Modifies how much stamina is lost when crouching.
* ``sv_crouch_stamina_slow_movement`` - (``0/1``)
  * Slows movement by using crouch stamina.
