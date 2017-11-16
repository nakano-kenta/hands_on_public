module Robot
  BOT = false.freeze

  def self.attr_state(*names)
    names.each{|n|
      n = n.to_sym
      attr_writer n
      attr_reader n
    }
  end

  def self.attr_action(*names)
    names.each{|n|
      n = n.to_sym
      define_method(n){|param| @actions[n] = param }
    }
  end

  def self.attr_event(*names)
    names.each{|n|
      n = n.to_sym
      define_method(n){ @events[n] }
    }
  end

  def self.attr_style(*names)
    names.each{|n|
      n = n.to_sym
      define_method(n){|param| @styles[n] = param }
    }
  end

  #the state hash of your robot. also accessible through the attr_state methods
  attr_accessor :state

  #the action hash of your robot
  attr_accessor :actions

  #the event hash of your robot
  attr_accessor :events

  #path to where your robot's optional skin images are
  attr_accessor :skin_prefix

  #team of your robot
  attr_accessor :team
  attr_accessor :team_members
  attr_accessor :name

  #the height of the battlefield
  attr_state :battlefield_height

  #the width of the battlefield
  attr_state :battlefield_width

  #your remaining energy (if this drops below 0 you are dead)
  attr_state :energy

  #the heading of your gun, 0 pointing east, 90 pointing north, 180 pointing west, 270 pointing south
  attr_state :gun_heading

  #your gun heat, if this is above 0 you can't shoot
  attr_state :gun_heat

  #your robots heading, 0 pointing east, 90 pointing north, 180 pointing west, 270 pointing south
  attr_state :heading

  #your robots radius, if x <= size you hit the left wall
  attr_state :size

  #the heading of your radar, 0 pointing east, 90 pointing north, 180 pointing west, 270 pointing south
  attr_state :radar_heading

  #ticks since match start
  attr_state :time

  #whether the match is over or not, remember to go into cheer mode when this is true ;)
  attr_state :game_over

  #your speed (-8..8)
  attr_state :speed
  alias :velocity :speed

  #your x coordinate, 0...battlefield_width
  attr_state :x

  #your y coordinate, 0...battlefield_height
  attr_state :y

  #accelerate (max speed is 8, max accelerate is 1/-1, negativ speed means moving backwards)
  attr_action :accelerate

  #accelerates negativ if moving forward (and vice versa), may take 8 ticks to stop (and you have to call it every tick)
  def stop
    accelerate -speed
  end

  #fires a bullet in the direction of your gun, power is 0.1 - 3, this power is taken from your energy
  attr_action :fire

  #turns the robot (and the gun and the radar), max 10 degrees per tick
  attr_action :turn

  #turns the gun (and the radar), max 30 degrees per tick
  attr_action :turn_gun

  #turns the radar, max 60 degrees per tick
  attr_action :turn_radar

  #broadcast message to other robots
  attr_action :broadcast

  #say something to the spectators
  attr_action :say

  #if you got hit last turn, this won't be empty
  attr_event :got_hit

  #distances to robots your radar swept over during last tick
  attr_event :robot_scanned

  #broadcasts received last turn
  attr_event :broadcasts

  attr_action :team_message
  attr_event :team_messages

  attr_state :num_robots
  attr_state :gui
  attr_state :round
  attr_accessor :durable_context
  attr_style :font_color
  attr_style :body_color
  attr_style :turret_color
  attr_style :radar_color
  attr_accessor :styles
  def game_over
  end

  attr_accessor :enable_callbacks
  def turned
  end

  def auto_turn(angle)
    @_auto_turn_angle = angle
  end

  def accelerated
  end

  def auto_accelerate(amount)
    @_auto_accelerate_amount = amount
    @_auto_stop = nil
  end

  def stopped
  end

  def auto_stop
    @_auto_stop = true
    @_auto_accelerate_amount = nil
  end

  def gun_turned
  end

  def auto_turn_gun(angle)
    @_auto_turn_gun_angle = angle
  end

  def radar_turned
  end

  def auto_turn_radar(angle)
    @_auto_turn_radar_angle = angle
  end

  def scanned(robots)

  end

  def crashed_into_enemy(events)
  end

  def crashed_into_wall(events)
  end

  def hit(events)
  end

  def got_hit(events)
  end

  def auto events
    if @enable_callbacks
      scanned events['robot_scanned'] if events['robot_scanned'].length > 0
      crashed_into_enemy events['crash_into_enemy'] if events['crash_into_enemy'].length > 0
      crashed_into_wall events['crash_into_wall'] if events['crash_into_wall'].length > 0
      hit events['hit'] if events['hit'].length > 0
      got_hit events['got_hit'] if events['got_hit'].length > 0
      if @_auto_turn_angle == 0
        turned
        @_auto_turn_angle = nil
      end
      if @_auto_accelerate_amount == 0
        accelerated
        @_auto_accelerate_amount = nil
      end
      if @_auto_stop and speed.abs < 0.001
        stopped
        @_auto_stop = nil
      end
      if @_auto_turn_gun_angle == 0
        gun_turned
        @_auto_turn_gun_angle = nil
      end
      if @_auto_turn_radar_angle == 0
        radar_turned
        @_auto_turn_radar_angle = nil
      end
    end

    if @_auto_turn_angle.to_f != 0
      turn_angle = [[@_auto_turn_angle, 10].min, -10].max
      @_auto_turn_angle -= turn_angle
      @_auto_turn_angle = 0 if @_auto_turn_angle.abs < 0.001
      turn turn_angle
    end
    if @_auto_accelerate_amount.to_f != 0
      accelerate_amount = [[@_auto_accelerate_amount, 1].min, -1].max
      @_auto_accelerate_amount -= accelerate_amount
      @_auto_accelerate_amount = 0 if @_auto_accelerate_amount.abs < 0.001
      accelerate accelerate_amount
    end
    if @_auto_stop
      stop
    end
    if @_auto_turn_gun_angle.to_f != 0
      turn_gun_angle = [[@_auto_turn_gun_angle, 45].min, -45].max
      @_auto_turn_gun_angle -= turn_gun_angle
      @_auto_turn_gun_angle = 0 if @_auto_turn_gun_angle.abs < 0.001
      turn_gun turn_gun_angle
    end
    if @_auto_turn_radar_angle.to_f != 0
      turn_radar_angle = [[@_auto_turn_radar_angle, 45].min, -45].max
      @_auto_turn_radar_angle -= turn_radar_angle
      @_auto_turn_radar_angle = 0 if @_auto_turn_radar_angle.abs < 0.001
      turn_radar turn_radar_angle
    end
  end
end
