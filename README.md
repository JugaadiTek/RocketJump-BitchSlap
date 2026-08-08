# RocketJump-BitchSlap
- **GODOT Version:** `4.7`

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


IGNORE THE ATTACHED IMAGE.
- Planets are all the same colors and size.
  - Editing the dictionary in OrbitalBody.gd does not impact size, or color, but does impact orbital speed.
- Players bounce too easily off of planets.
  - Players should default to running and jumping around the spheres like one would normally run around in quake 3 arena.
  - Only rocket jumps, jump pads or impacts from  other players should have the ability to launch players into orbit.
