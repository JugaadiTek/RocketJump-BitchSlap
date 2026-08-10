# RocketJump-BitchSlap
- **GODOT Version:** `4.7.1`

## Overview
This is a Video Game Concept Prototype project built in Godot.

Rocketjump BitchSlap is a game reminiscent of Quake 3 Arena, with similar movement, but with some twists. The players Play in an arena with several miniature planet-like orbs are orbiting each other using their rocket launchers to rocket jump from one orb to another while shooting at each other. Rockets move slow and are affected by the sudo gravity of the orbs to create slingshot arcs to enhance gameplay.

A Standard First Person Shooter Player Controller inspired by Quake 3 Arenas Feel and Controls.

## ClaudeCode Links
- Initial Draft: https://claude.ai/share/21d639c5-98a1-46de-a3a3-4e96f31f6abb

### Weapons
- A Rocket Launcher the launches slow moving projectiles
	- No Self Damage and a rocket jump mechanic.
		- Can use rocket jumps to navigate between different orbs, or when not touching a planet/orb to change the direction of movement.
	- Rockets hitting planets change their orbits by 0.01% to 0.1% to create a gradual chaotic shift to the arena and emergent gameplay opertunities.
- Mele Attack: "The Bitchslap" -> grab a player in range, smack their face, then a piston attached to the player slams into them killing them and sending their body flying away.
	- If smacked downward: it sends the player launching into orbit.
	- If Smacked outwards & the defeated enemies body hits another planet orb, it changes its orbit appropriately.
- **Rail Gun:** that uses a raycast to instantly determine hits.
- **Slug Gun:** A slug launcher weapon that launches alien slugs which ooze along the surface of the plaents to chase down other players.
- **The Planet Buster:** A slow moving Weapon that spawns rarely and can be used to break the orb planets apart and kill everyone within a certain radius.
	- Single shot, the whole weapon is literally a hand held missile without a launcher. It is a one shot weapon that can be used to destroy planets and kill everyone on them.
- **Portal Gun:** 
	- Can be used to create a portal on a planet surface and another portal on another planet surface to create a wormhole between the two planets.
	- Players can use this to quickly navigate between planets or to escape from enemies. 

## **Game Features:**
- A Starter Arena with 2 orbiting spheres in the center and several other spheres orbiting the central two. The smallest sphere a players should be able to run around it in any direction in less than 15 seconds, the largest sphere should take 2 minutes to run around the surface.
   - Do not perfectly emulate physics, focus on fun gameplay and ridiculous moments.
- Basic NPC opponent AI logic.
- Basic IP Connect Multiplayer.

### Next Steps:
- Please revert the changes related to flight control.
	- Players are flying off the planets too easily. Once they have landed they should move normally along the surface.
- Outer boundary should launch players at a much higher speed towards the nearest planet with a guided trajectory and a managed landing.
- Set the standard number of total players including bots to always be 32.
- Rail Gun:
	- Make the rail gun have a charge up time before it can fire, and make it so that the longer the player holds the fire button, the more damage it does.
	- Add a sniping scope to the rail gun that allows players to zoom in and aim more accurately.

### Next Steps:
- GUI
	- Add a FPS counter to the top left corner of the screen.
	- Score Board: Make it scroll and have a max height of 80% of the screen, default scroll position with the current player highlighted and visible.
- Planets:
	- Allow Eliptical Orbits to form.
	- Give each planet a random spin and axis tilt.
	- If a planets orbit hits the outside of the arena, destroy it and spawn 1-3 smaller orbs to launch towards the center of the system targeting stable orbits around other orbs.
	- Spawn a variety of Buildings with navigateable interiors on the Planets to provide places to seek cover and fire from.
		- Spawn 0-3 Towers on each planet that can be used to gain a height advantage over other players. The tower height should be equal to the radius of the planet it is on.
- Players and Bots:
	- Weapons:
		- General Update:
			- Momentum of the projectiles should be on offset of the players current momentum when they fire the weapon. (for example if a player is moving forward and fires a rocket, the rocket should have a forward momentum in addition to its own speed so that it doesn't shoot behind the player if they are moving forward).
		- New Weapons:
			- The Space Board: 
				- can only switch too when they are not on a planet.
				- allows players to change their trajectory in mid air.
				- A hand held jet pack held in front of the player like a boogie board.
			- Grappling Hook:
				- can be used to grapple onto planets or buildings and pull the player towards them.
				- can be used to grapple onto other players and pull them towards the player.
		- Update Existing Weapons:
			- Rail Gun:
				- Add a sniper scope model to the rail gun with a zoom in feature.
			- Planet Buster: 
				- Make the weapon crosshairs lock on a planet in its sites, then the weapon auto navigates to that planet. 
				- Not able to target planets that are too close... (no suicide shots).
				- When planet is destroy it is busted apart into 2-5 smaller rogue satelites that become moons for other planets in the system.
			- Slug Gun:
				- Give The Slugs that are shot out of the slug gun a small amount of hit points, and allow them to take damage from other (non-slug) weapons.
				- Make the weapon a medium speed automatic. (hold fire button)
			- Rocket Launcher:
				- Deforms Planet Mesh in the blast radius on contact.
				- add a particle effect smoke trail for the rockets.
	- Spawning and Respawning:
		- When a player spawns, they start facing the orbiting bodies from the outermost barrier. 
			- They have 10 seconds to choose a target planet to launch towards, by holding the fire button while aiming at it.
			- when a planet is in their sights the crosshairs should turn green and have a locked box around them. 
			- if they dont select a planet in 10 seconds, they will be launched towards the closest planet to them.
		- They then shoot in on a fast trajectory to land on their choice planet from their current position.
			- leaving a trail of particles behind them.
			- A smoke bomb where they land.
			- Impact the planets Orbit by 0.1% to 0.3%.
	- Bots
		- Create a Dictionary of random names for the bots to choose from when they spawn.
		- Make the Bots also seek out and target each other
			- add a random variance range to bot attack accuracy with lower and upper bounds.
			- for slower weapons have their shots lead the opponents movement.


### For Avinash
Bugs:

* The player bounces when moving across a planet even when not jumping.
* Sometimes when trying to stand still on a planet, the planet slides under  the player rather than the player staying stationary to the planet.
* Sometimes when circumnavigating a planet, it feels like the player hits an invisible wall and is not able to move forward in a given direction.

Improvements:

* The grappling hook should shoot and release a cable when being used.
* The boogie board should allow full freedom of movement in any direction.
* The planet buster should only fire when locked onto a planet and start slow but have linear acceleration until it collides with the planet, updating its path every 1s.
