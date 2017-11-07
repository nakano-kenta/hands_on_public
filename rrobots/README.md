# How to setup
```
brew install sdl2
bundle install
```

# How to play
```
RUBYLIB=lib bundle exec ./bin/rrobots --resolution=1500,1500 tanks/simple.rb tanks/simple.rb
```

# Based on
https://github.com/logankoester/rrobots

# Study
`Win means at least 9 wins in 10 battles !!`

## Entry level (700x700)
1. Win against Simple
   Need to turn gun effectively.
2. Win against Shooter
   Need move to avoid getting hit.
3. Win against Shooter
   Need move to avoid getting hit.

## Basic level(700x700)
10. Win against Aiming
   Need move complicatedly.
11. Win against Wall
   Need to aim uniform speed liner moving targets.
12. Win against Circle
   Need to aim uniform acceleration moving targets.
13. Win against Swing
   Need to aim patterned moving targets.

## Advansed level(700x700)
20. Win against WallShooter
21. Win against CircleShooter
22. Win against SwingShooter

## Master1(1000x1000)
23. Win against WallShooter, CircleShooter and SwingShooter

## Master2(700x700)
31. Win against WallWithAiming
32. Win against CircleWithAiming
33. Win against SiwingWithAiming

## Master3(1000x1000)
34. Win against WallWithAiming, CircleWithAiming and SwingWithAiming

## Master4(700x700)
50. Win against RandomShooter

## Hell(1500x1500) (勝てるもんなら勝ってみろ！！)
777. Win against Kubota

# Robot interface
## Definitions
* **battlefield_height** - the height of the battlefield
* **battlefield_width** - the width of the battlefield
* **size** - your robots radius, if x <= size you hit the left wall

## Global attributes
* **time** - ticks since match start
* **num_robots** - number of living robots
* **gui** - true if GUI enabled
* **round** - the number of rounds of matches

## Robot status
* **energy** - your remaining energy (if this drops below 0 you are dead)
* **speed** - your speed (-8..8)
* **gun_heading** - the heading of your gun, 0 pointing east, 90 pointing north, 180 pointing west, 270 pointing south
* **gun_heat** - your gun heat, if this is above 0 you can't shoot
* **heading** - your robots heading, 0 pointing east, 90 pointing north, 180 pointing west, 270 pointing south
* **radar_heading** - the heading of your radar, 0 pointing east, 90 pointing north, 180 pointing west, 270 pointing south
* **x** - your x coordinate, 0...battlefield_width
* **y** - your y coordinate, 0...battlefield_height

## Robot actions
* **accelerate** - accelerate (max speed is 8, max accelerate is 1/-1, negativ speed means moving backwards)
* **fire** - fires a bullet in the direction of your gun, power is 0.1 - 3, this power is taken from your energy
* **turn** - turns the robot (and the gun and the radar), max 10 degrees per tick
* **turn_gun** - turns the gun (and the radar), max 30 degrees per tick
* **turn_radar** - turns the radar, max 60 degrees per tick

## Robot storage
* **durable_context** - durable context among all matches
