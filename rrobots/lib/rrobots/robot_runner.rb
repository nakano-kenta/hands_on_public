require 'securerandom'

class RobotRunner

  STATE_IVARS = [ :x, :y, :gun_heat, :heading, :gun_heading, :radar_heading, :time, :size, :speed, :energy, :team ]
  NUMERIC_ACTIONS = [ :fire, :turn, :turn_gun, :turn_radar, :accelerate ]
  STRING_ACTIONS = [ :say, :broadcast ]

  STATE_IVARS.each{|iv|
    attr_accessor iv
  }
  NUMERIC_ACTIONS.each{|iv|
    attr_accessor "#{iv}_min", "#{iv}_max"
  }
  STRING_ACTIONS.each{|iv|
    attr_accessor "#{iv}_max"
  }

  #AI of this robot
  attr_accessor :robot

  #team of this robot
  attr_accessor :team

  #keeps track of total damage done by this robot
  attr_accessor :damage_given
  attr_accessor :damage_taken
  attr_accessor :bullet_damage_given
  attr_accessor :bullet_damage_taken
  attr_accessor :ram_damage_given
  attr_accessor :ram_damage_taken
  attr_accessor :ram_kills

  #keeps track of the kills
  attr_accessor :kills

  attr_reader :actions, :speech

  attr_accessor :events
  attr_accessor :prev_x
  attr_accessor :prev_y
  attr_accessor :prev_speed

  def initialize robot, bf, team, options
    @robot = robot
    @battlefield = bf
    @team = team
    set_action_limits
    set_initial_state
    @events = Hash.new{|h, k| h[k]=[]}
    @actions = Hash.new(0)
  end

  def skin_prefix
    @robot.skin_prefix
  end

  def set_initial_state
    @x = @battlefield.width / 2
    @y = @battlefield.height / 2
    @prev_x = @x
    @prev_y = @y
    @speech_counter = -1
    @speech = nil
    @time = 0
    @size = 60
    @speed = 0
    @energy = 100
    @damage_given = 0
    @damage_taken = 0
    @bullet_damage_given = 0
    @bullet_damage_taken = 0
    @ram_damage_given = 0
    @ram_damage_taken = 0
    @ram_kills = 0
    @kills = 0
    teleport
  end

  def teleport(distance_x=(@battlefield.width/2)-@size*2, distance_y=(@battlefield.height/2)-@size*2)
    @x += ((SecureRandom.random_number-0.5) * 2 * distance_x).to_i
    @y += ((SecureRandom.random_number-0.5) * 2 * distance_y).to_i
    @gun_heat = 3
    @heading = (SecureRandom.random_number * 360).to_i
    @gun_heading = @heading
    @radar_heading = @heading
    @old_radar_heading = @radar_heading
    @new_radar_heading = @radar_heading
  end

  def set_action_limits
    @fire_min, @fire_max = 0, 3
    @turn_min, @turn_max = -10, 10
    @turn_gun_min, @turn_gun_max = -30, 30
    @turn_radar_min, @turn_radar_max = -60, 60
    @accelerate_min, @accelerate_max = -1, 1
    @teleport_min, @teleport_max = 0, 100
    @say_max = 256
    @broadcast_max = 16
  end

  def hit bullet
    damage = bullet.energy
    @energy -= damage
    @events['got_hit'] << {
      from: bullet.origin.name,
      damage: damage,
    }
    if !bullet.origin.dead
      bullet.origin.energy += damage * 2/3
      bullet.origin.events['hit'] << {
        to: name,
        damage: damage
      }
    end
    damage
  end

  def dead
    @energy <= 0
  end

  def zonbi?
    @energy <= 0.3
  end

  def clamp(var, min, max)
    val = 0 + var # to guard against poisoned vars
    if val > max
      max
    elsif val < min
      min
    else
      val
    end
  end

  def internal_tick
    scan
    update_state
    robot_tick
    parse_actions
    fire
    turn
    move
    speak
    broadcast
    @time += 1
  end

  def impact_to_damage(impact)
    impact * impact / 10
  end

  def diff_angle(a, b)
    diff = a - b
    if diff > 180
      diff -= 360
    elsif diff < -180
      diff += 360
    end
    diff
  end

  def after_tick
    @battlefield.robots.each do |other|
      if (other != self) && (!other.dead)
        difference = Math.hypot(@y - other.y, other.x - @x)
        if difference <= @size * 2 and !@events['crash_into_enemy'].any?{|event| event[:with] == other.name}
          dx = Math::cos(@heading.to_rad) * @speed
          dy = -Math::sin(@heading.to_rad) * @speed
          other_dx = Math::cos(other.heading.to_rad) * other.speed
          other_dy = -Math::sin(other.heading.to_rad) * other.speed
          @x = @prev_x + (dx + other_dx) / 4
          @y = @prev_y + (dy + other_dy) / 4

          direction = to_direction({x: @prev_x, y: @prev_y}, {x: @x, y: @y})
          @speed = Math.hypot(@prev_y - @y, @x - @prev_x) * Math.cos(diff_angle(direction, @heading) / 180 * Math::PI)
          after_move

          other.x = other.prev_x + (dx + other_dx) / 4
          other.y = other.prev_y + (dy + other_dy) / 4

          other_direction = to_direction({x: other.prev_x, y: other.prev_y}, {x: other.x, y: other.y})

          other.speed = Math.hypot(other.prev_y - other.y, other.x - other.prev_x) * Math.cos(diff_angle(other_direction, other.heading) / 180 * Math::PI)
          other.after_move
          impact = Math.hypot(dy - other_dy, dx - other_dx)
          damage = impact_to_damage(impact)
          @energy -= damage
          @ram_damage_taken += damage
          @ram_damage_given += damage
          other.energy -= damage
          other.ram_damage_taken += damage
          other.ram_damage_given += damage
          if other.dead
            @kills += 1
            @ram_kills += 1
          end
          if dead
            other.kills += 1
            other.ram_kills += 1
          end
          @events['crash_into_enemy'] << {
            with: other.name,
            damage: damage
          }
          other.events['crash_into_enemy'] << {
            with: name,
            damage: damage
          }
        end
      end
    end
  end

  def parse_actions
    @actions.clear
    NUMERIC_ACTIONS.each{|an|
      @actions[an] = clamp(@robot.actions[an], send("#{an}_min"), send("#{an}_max"))
    }
    STRING_ACTIONS.each{|an|
      if @robot.actions[an] != 0
        @actions[an] = String(@robot.actions[an])[0, send("#{an}_max")]
      end
    }
    @actions
  end

  def state
    current_state = {}
    STATE_IVARS.each{|iv|
      current_state[iv] = send(iv)
    }
    current_state[:battlefield_width] = @battlefield.width
    current_state[:battlefield_height] = @battlefield.height
    current_state[:game_over] = @battlefield.game_over
    current_state[:num_robots] = @battlefield.robots.reject{|robot| robot.dead}.length
    current_state
  end

  def update_state
    new_state = state
    @robot.state = new_state
    new_state.each{|k,v|
      @robot.send("#{k}=", v) if @robot.respond_to? "#{k}="
    }
    @robot.events = @events.dup
    @robot.actions ||= Hash.new(0)
    @robot.actions.clear
  end

  def robot_tick
    unless zonbi?
      @robot.tick @robot.events
    end
    @events.clear
  end

  def fire
    return if zonbi?
    @actions[:fire] = (@energy - 0.1) if @actions[:fire] > @energy
    if (@actions[:fire] > 0) && (@gun_heat == 0)
      bullet = Bullet.new(@battlefield, @x, @y, @gun_heading, 30, @actions[:fire]*3.3 , self)
      3.times{bullet.tick}
      @battlefield << bullet
      @gun_heat = 0.5 + @actions[:fire] / 1.2
      @energy -= @actions[:fire]
    end
    @gun_heat -= 0.1
    @gun_heat = 0 if @gun_heat < 0
  end

  def turn
    @old_radar_heading = @radar_heading
    @heading += @actions[:turn]
    @gun_heading += (@actions[:turn] + @actions[:turn_gun])
    @radar_heading += (@actions[:turn] + @actions[:turn_gun] + @actions[:turn_radar])
    @new_radar_heading = @radar_heading

    @heading %= 360
    @gun_heading %= 360
    @radar_heading %= 360
  end

  def move
    @speed = 0 if zonbi?
    @prev_speed = @speed
    @prev_x = @x
    @prev_y = @y
    @prev_heading = @heading

    @speed += @actions[:accelerate]
    @speed = 8 if @speed > 8
    @speed = -8 if @speed < -8

    @x += Math::cos(@heading.to_rad) * @speed
    @y -= Math::sin(@heading.to_rad) * @speed

    after_move
  end

  def after_move
    if @x - @size < 0 or @y - @size < 0 or @x + @size >= @battlefield.width or @y + @size >= @battlefield.height
      @x = @size if @x - @size < 0
      @y = @size if @y - @size < 0
      @x = @battlefield.width - @size if @x + @size >= @battlefield.width
      @y = @battlefield.height - @size if @y + @size >= @battlefield.height
      impact = @speed.abs - Math.hypot(@y - @prev_y, @x - @prev_x)
      if impact > 0.1
        @speed = 0
        damage = impact_to_damage(impact)
        @energy -= damage
        @ram_damage_taken += damage
        @events['crash_into_wall'] << {
          damage: damage
        }
      end
    end
  end

  def to_angle(radian)
    (radian * 180.0 / Math::PI + 360) % 360
  end

  def to_direction(a, b)
    diff_x = a[:x] - b[:x]
    diff_y = b[:y] - a[:y]
    to_angle(Math.atan2(diff_y, diff_x) - Math::PI)
  end

  def scan
    @battlefield.robots.each do |other|
      if (other != self) && (!other.dead)
        a = Math.atan2(@y - other.y, other.x - @x) / Math::PI * 180 % 360
        if (@old_radar_heading <= a && a <= @new_radar_heading) || (@old_radar_heading >= a && a >= @new_radar_heading) ||
          (@old_radar_heading <= a+360 && a+360 <= @new_radar_heading) || (@old_radar_heading >= a+360 && a+360 >= new_radar_heading) ||
           (@old_radar_heading <= a-360 && a-360 <= @new_radar_heading) || (@old_radar_heading >= a-360 && a-360 >= @new_radar_heading)
          @events['robot_scanned'] << {
            distance: Math.hypot(@y - other.y, other.x - @x),
            direction: to_direction({x: @x, y: @y}, {x: other.x, y: other.y}),
            energy: other.energy,
            name: other.name
          }
        end
      end
    end
  end

  def speak
    if @actions[:say] != 0
      @speech = @actions[:say]
      @speech_counter = 50
    elsif @speech and (@speech_counter -= 1) < 0
      @speech = nil
    end
  end

  def broadcast
    @battlefield.robots.each do |other|
      if (other != self) && (!other.dead)
        msg = other.actions[:broadcast]
        if msg != 0
          a = Math.atan2(@y - other.y, other.x - @x) / Math::PI * 180 % 360
          dir = 'east'
          dir = 'north' if a.between? 45,135
          dir = 'west' if a.between? 135,225
          dir = 'south' if a.between? 225,315
          @events['broadcasts'] << [msg, dir]
        end
      end
    end
  end

  def to_s
    @robot.class.name
  end

  def name
    @robot.class.name
  end
end
