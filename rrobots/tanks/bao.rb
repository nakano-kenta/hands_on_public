require 'rrobots'
require 'securerandom'

  #  battlefield_height  #the height of the battlefield
  #  battlefield_width   #the width of the battlefield
  #  energy              #your remaining energy (if this drops below 0 you are dead)
  #  gun_heading         #the heading of your gun, 0 pointing east, 90 pointing
  #                      #north, 180 pointing west, 270 pointing south
  #  gun_heat            #your gun heat, if this is above 0 you can't shoot
  #  heading             #your robots heading, 0 pointing east, 90 pointing north,
  #                      #180 pointing west, 270 pointing south
  #  size                #your robots radius, if x <= size you hit the left wall
  #  radar_heading       #the heading of your radar, 0 pointing east,
  #                      #90 pointing north, 180 pointing west, 270 pointing south
  #  time                #ticks since match start
  #  speed               #your speed (-8/8)
  #  x                   #your x coordinate, 0...battlefield_width
  #  y                   #your y coordinate, 0...battlefield_height
  #  accelerate(param)   #accelerate (max speed is 8, max accelerate is 1/-1,
  #                      #negativ speed means moving backwards)
  #  stop                #accelerates negativ if moving forward (and vice versa),
  #                      #may take 8 ticks to stop (and you have to call it every tick)
  #  fire(power)         #fires a bullet in the direction of your gun,
  #                      #power is 0.1 - 3, this power will heat your gun
  #  turn(degrees)       #turns the robot (and the gun and the radar),
  #                      #max 10 degrees per tick
  #  turn_gun(degrees)   #turns the gun (and the radar), max 30 degrees per tick
  #  turn_radar(degrees) #turns the radar, max 60 degrees per tick
  #  dead                #true if you are dead
  #  say(msg)            #shows msg above the robot on screen
  #  broadcast(msg)      #broadcasts msg to all bots (they recieve 'broadcasts'
  #                      #events with the msg and rough direction)

class Bao
  include Robot
  TURN_TANK_MAX = 10
  TURN_GUN_MAX = 30
  TURN_RADAR_MAX = 60
  SPEED_MAX = 8
  FIRE_MAX = 3
  FIRE_MIN = 0.1
  MAX_ACCELERATE = 1

  def initialize
    @self_info = {}
    @enemy_info = {}

    @will_turn_tank_degree = false
    @will_turn_gun_degree = false
    @will_turn_radar_degree = false
    @will_change_acc_step = false
    @will_fire = false

    @turn_tank_degree = 0
    @tank_direction = 1
    @turn_gun_degree= 0
    @gun_direction = 1
    @turn_radar_degree= TURN_RADAR_MAX
    @radar_direction = 1

    @acc_step = 1
  end

  def field_limit
    {x: battlefield_width * 0.15, y: battlefield_height * 0.15}
  end

  def update_self_info
    if @self_info[time-1]
      heading_changed = (heading - @self_info[time-1][:heading]) % 360
      if heading_changed > 180
        heading_changed -= 360
      end
      gun_heading_changed = (gun_heading - @self_info[time-1][:gun_heading]) % 360
      if gun_heading_changed > 180
        gun_heading_changed -= 360
      end
      radar_heading_changed = (radar_heading - @self_info[time-1][:radar_heading]) % 360
      if radar_heading_changed > 180
        radar_heading_changed -= 360
      end

      energy_changed = energy - @self_info[time-1][:energy]
      speed_changed = speed - @self_info[time-1][:speed]
    end
    @self_info[time] = {
      position: current_position,
      heading: heading,
      heading_changed: heading_changed,
      gun_heading: gun_heading,
      gun_heading_changed: gun_heading_changed,
      radar_heading: radar_heading,
      radar_heading_changed: radar_heading_changed,
      energy: energy,
      energy_changed: energy_changed,
      speed: speed,
      speed_changed: speed_changed
    }
    @self_info[time][:scanned] = events['robot_scanned'] if events['robot_scanned'].size > 0
  end

  def update_enemy_info
    events['robot_scanned'].each do |enemy|
      @enemy_info[enemy[:name]] ||= {}
      @enemy_info[enemy[:name]][time] ||= {}
      @enemy_info[enemy[:name]][time][:last_time] =
      @enemy_info[enemy[:name]][time][:direction] = enemy[:direction]
      @enemy_info[enemy[:name]][time][:distance] = enemy[:distance]
      @enemy_info[enemy[:name]][time][:energy] = enemy[:energy]
      position = {
        x: x + Math.cos(degree_to_radians(enemy[:direction])) * enemy[:distance],
        y: y - Math.sin(degree_to_radians(enemy[:direction])) * enemy[:distance]
      }
      @enemy_info[enemy[:name]][time][:position] = position
    end
  end

  def tick events
    update_self_info
    update_enemy_info
    move
    turn_gun_direction
    turn_radar_direction
    open_fire
  end

  #robot_scanned element
  #{:distance, :direction, :energy_hp, :energy_name}

  def was_hitted?
    return true if energy_info[time].to_f < energy_info[time - 1].to_f
    return false
  end

  def current_position
    {x: x, y: y}
  end

  def center_position
    {x: battlefield_width/2, y: battlefield_height/2}
  end

  def near_wall?
    x < size + field_limit[:x] or y < size + field_limit[:y] or x > (battlefield_width - size - field_limit[:x]) or y > (battlefield_height - size - field_limit[:y])
  end

  def on_wall?
    if x <= size or y <= size or x >= battlefield_width - size or y >= battlefield_height - size
      @hit_wall = 'west'  if x <= size
      @hit_wall = 'north' if y <= size
      @hit_wall = 'east'  if x >= battlefield_width - size
      @hit_wall = 'south' if y >= battlefield_height - size
      return true
    else
      @hit_wall = 0
      return false
    end
  end

  def degree_to_radians degree
    degree * Math::PI / 180
  end


  def degree_to_direction degree
    degree = degree % 360
    degree -= 360 if degree > 180
    degree += 360 if degree < -180
    degree
  end


  def random_accelerate(n, random=true)
    if random and SecureRandom.random_number < 0.3
      n = -1 * (SecureRandom.random_number(10) / 10.0)
    end
    accelerate n
    #pp "accelerate: #{n}"
  end

  def move
    turn_tank_direction
    make_acceleration
  end

  def make_acceleration
    if near_wall?
      random_accelerate @acc_step * (-1), false
    else
      random_accelerate @acc_step
    end
  end

  def turn_gun_direction
    @self_info[time][:scanned]
    if events['robot_scanned'].size > 0
      events['robot_scanned'].each do |enemy|
        diff = degree_to_direction(enemy[:direction] -gun_heading) - @turn_tank_degree
        if diff.abs <= TURN_GUN_MAX
          @turn_gun_degree = diff
          @will_fire = true if gun_heat == 0
        else
          @turn_gun_degree = diff > 0 ? TURN_GUN_MAX : TURN_GUN_MAX * (-1)
        end
        #pp "now gun_heading: #{gun_heading} next should be: #{gun_heading + @turn_gun_degree}"
        turn_gun @turn_gun_degree
      end
    end
  end

  def turn_radar_direction
    @turn_radar_degree =
      if events['robot_scanned'].size > 0
        @turn_radar_degree * -1 - @turn_gun_degree - @turn_tank_degree
      else
        @turn_radar_degree - @turn_gun_degree - @turn_tank_degree
      end
    #pp "now radar_heading: #{radar_heading} next should be: #{radar_heading + @turn_radar_degree}"
    turn_radar @turn_radar_degree
  end

  def turn_tank_direction
    if events['robot_scanned'].size > 0
      events['robot_scanned'].each do |enemy|
        move_target_left  = degree_to_direction(enemy[:direction] - 90)
        move_target_right = degree_to_direction(enemy[:direction] + 90)
        diff = (move_target_left - heading).abs < (move_target_right - heading).abs \
          ? move_target_left - heading : move_target_right - heading
        if diff.abs < TURN_TANK_MAX
          @turn_tank_degree = diff
        else
          @turn_tank_degree = diff > 0 ? TURN_TANK_MAX : TURN_TANK_MAX * (-1)
        end
        #pp "heading: #{heading} enemy: #{enemy[:direction]} diff: #{diff} next should be: #{heading + @turn_tank_degree}"
        if near_wall?
          #@turn_tank_degree *= -1
        end
        turn @turn_tank_degree
      end
    else
      @turn_tank_degree = 0
    end
  end

  def open_fire
    if @will_fire
      fire 3
      @will_fire = false
    end
  end

end
