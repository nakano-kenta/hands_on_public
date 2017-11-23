require 'rrobots'

class Sekine
  include Robot

  LOST_TICK = 10
  MAX_HISTORY_SIZE = 1000
  MAX_SPEED = 8
  NORMAL_SPEED = 4
  MAX_RADAR_TURN = 60.to_rad
  MAX_GUN_TURN  = 30.to_rad
  MAX_TURN = 10.to_rad
  BULLET_SPPED = 30
  DEFAULT_KEEPED_DISTANCE = 500
  NEALY_DISTANCE = 70
  WALL_DISTANCE_LIMIT = 0.3
  DEFAULT_TURN_TIME = 120
  EMERGENCY_TIME = 15

  def position(x_positioin = nil, y_positioin = nil)
    { x: x_positioin || x, y: y_positioin || y }
  end

  def before_start
    @enable_log = false
    @enable_debug_line = false
    @enable_rador_line = false
    @enable_tank_line = false
  end

  def init
    @histories = {}
    @target = nil
    @center = position(battlefield_width / 2, battlefield_height / 2)
    @keeped_distance = DEFAULT_KEEPED_DISTANCE
    @next_turn_time = DEFAULT_TURN_TIME
    @last_turn_time = 0
    @direction = 1
    @emergency = 0
    @will_fire = 0

    term_frame
  end

  def init_frame(events)
    @will_turn = 0
    @will_turn_gun = 0
    @will_turn_radar = 0

    @current_position = position(x, y)
    @emergency = EMERGENCY_TIME if @emergency <= 0 and enemy_shot?

    unless events['robot_scanned'].empty?
      min_distance = nil
      events['robot_scanned'].each do |scanned|
        scanned[:time] = time
        scanned[:position] = to_position(scanned[:direction].to_rad, scanned[:distance], @current_position)
        @histories[scanned[:name]] ||= []
        @histories[scanned[:name]] << scanned
        @histories[scanned[:name]].shift if @histories[scanned[:name]].size > MAX_HISTORY_SIZE
        if min_distance.nil? or min_distance > scanned[:distance]
          @target = scanned[:name]
          min_distance = scanned[:distance]
        end
      end
    end
  end

  def do_turn
    @will_turn = sign(@will_turn) * [@will_turn.abs, MAX_TURN].min
    @will_turn_gun = sign(normalize_radian(@will_turn_gun - @will_turn)) * [normalize_radian(@will_turn_gun - @will_turn).abs, MAX_GUN_TURN].min
    @will_turn_radar = sign(normalize_radian(@will_turn_radar - @will_turn_gun - @will_turn)) * [normalize_radian(@will_turn_radar - @will_turn_gun - @will_turn).abs, MAX_RADAR_TURN].min
    turn to_angle(@will_turn)
    turn_gun to_angle(@will_turn_gun)
    turn_radar to_angle(@will_turn_radar)
  end

  def term_frame
    @emergency -= 1
    @last_position = position(x, y)
    @last_heading = heading
    @last_gun_heading = gun_heading
    @last_radar_heading = radar_heading
    @last_speed = speed
  end

  def last_target_events(count = 1)
    return nil if @histories[@target].nil?
    count = [count, @histories[@target].size].min
    @histories[@target][-1 * count, count]
  end

  def enemy_shot?
    # TODO: exclude my shot!
    target_events = last_target_events(2)
    return false if target_events.nil? or target_events.size < 2
    target_events[0][:energy] < target_events[1][:energy]
  end

  def search
    target_events = last_target_events(2)
    radar_direction = 0
    if target_events.nil? or target_events.last[:time] < time - LOST_TICK
      radar_direction += MAX_RADAR_TURN
    else
      last_event = target_events.last
      if last_event[:time] == time
        radar_direction = normalize_radian(last_event[:direction].to_rad - radar_heading.to_rad)
        offset = Math.atan2(MAX_SPEED * 5, last_event[:distance])
        radar_direction += sign(radar_direction) * offset
        if @enable_rador_line
          draw_line(@current_position, to_position(radar_heading.to_rad, last_event[:distance], @current_position))
          draw_line(@current_position, to_position(radar_heading.to_rad + radar_direction, last_event[:distance], @current_position))
        end
      else
        radar_direction = normalize_radian(@last_radar_heading.to_rad - radar_heading.to_rad) * 2
      end
    end

    @will_turn_radar = radar_direction
  end

  def aiming
    gun_direction = nil
    last_event = last_target_events&.last
    unless last_event.nil?
      distnace_to_enemy = last_event[:distance]
      tick_for_hit = (distnace_to_enemy / BULLET_SPPED).ceil.to_i + 1
      target_events = last_target_events(tick_for_hit)
      if target_events.size < tick_for_hit or true
        a = target_events.first
        b = target_events.last
        if a[:position] == b[:position]
          future_position = a[:position]
        else
          enemy_direction = normalize_radian(to_direction(a[:position], b[:position]))
          move_distance = distance(a[:position], b[:position])
          future_position = to_position(enemy_direction, move_distance * tick_for_hit / (b[:time] - a[:time]), b[:position])
        end
        draw_point_rect(future_position)
        gun_direction = normalize_radian(to_direction(@current_position, future_position) - gun_heading.to_rad)
        @will_fire = 3.0 if gun_direction.abs < 0.01
      else
        # TODO: 
        # vectors = []
        # target_events.each do |event|

        # end
        # gun_direction = normalize_radian(target_events.last[:direction].to_rad - gun_heading.to_rad)
      end

      unless gun_direction.nil?
        @will_turn_gun = gun_direction
        draw_line(@current_position, to_position(gun_heading.to_rad, last_event[:distance], @current_position), 0xff_ff0000)
      end
    end
  end

  def safe_position?(position)
    @safe_area ||= {
      min_x: battlefield_width * WALL_DISTANCE_LIMIT,
      max_x: battlefield_width - (battlefield_width * WALL_DISTANCE_LIMIT),
      min_y: battlefield_height * WALL_DISTANCE_LIMIT,
      max_y: battlefield_height - (battlefield_height * WALL_DISTANCE_LIMIT),
    }
    @safe_area[:min_x] <= position[:x] and position[:x] <= @safe_area[:max_x] and @safe_area[:min_y] <= position[:y] and position[:y] <= @safe_area[:max_y]
  end

  def head_direction
    if @direction >= 0
      front = to_position(heading.to_rad, 100, @current_position)
      back = to_position(normalize_radian(heading.to_rad + Math::PI), 100, @current_position)
    else
      front = to_position(heading.to_rad + Math::PI, 100, @current_position)
      back = to_position(normalize_radian(heading.to_rad), 100, @current_position)
    end
    if safe_position?(front)
      @direction *= -1 if rand > 0.7 and safe_position?(back)
    elsif safe_position?(back) or distance(front, @center) > distance(back, @center)
      @direction *= -1
    end
  end

  def move
    if @next_turn_time <= time and @emergency <= 0
      head_direction
      @last_turn_time = time
      @next_turn_time = time + DEFAULT_TURN_TIME
    end

    tick = time - @last_turn_time
    moved_ratio = tick.to_f / (@next_turn_time - @last_turn_time)
    if moved_ratio < 0.5
      target_speed = [1, NORMAL_SPEED * moved_ratio * 2].max
    else
      target_speed = NORMAL_SPEED * (1.0 - moved_ratio) * 2
    end
    target_speed = MAX_SPEED if @emergency > 0
    target_speed *= @direction
    accelerate(target_speed - speed)

    last_events = last_target_events
    target_direction = heading
    unless last_events.nil?
      if last_events.size > 0
        offset = Math::PI / 6.0
        distance = distance(@current_position, last_events.last[:position])
        offset *= 2.0 if distance < NEALY_DISTANCE
        diff =  @keeped_distance - distance
        if diff < -10
          offset *= -1.0 * @direction
        elsif diff > 10
          offset *= @direction
        end
        target_direction = normalize_radian(to_direction(@current_position, last_events.last[:position]) + (offset + Math::PI / 2))
      end
    end

    @will_turn = normalize_radian(target_direction - heading.to_rad)
  end

  def tick events
    return if game_over
    init if time == 0
    init_frame(events)

    fire @will_fire if @will_fire > 0

    search
    aiming
    move
    do_turn

    term_frame
  end

  private
  def log(*msg)
    puts "#{time}: #{msg.join ' '}" if @enable_log
  end

  def sign(value)
    return 1 if value == 0
    (value / value.abs).round.to_i
  end

  def normalize_radian(radian)
    sign = radian / radian.abs
    radian -= sign * Math::PI * 2 while radian.abs > Math::PI
    radian
  end

  def to_angle(radian)
    angle = (radian * 180.0 / Math::PI + 360) % 360
    angle -= 360 if angle > 180
    angle
  end

  def add_position(a, b)
    { x: a[:x] + b[:x], y: a[:y] + b[:y] }
  end

  def to_position(radian, distance, base = nil)
    ret = {x: Math.cos(radian) * distance, y: - Math.sin(radian) * distance}
    ret = add_position(ret, base) if base
    ret
  end

  def distance(a, b)
    Math.hypot(a[:x] - b[:x], a[:y] - b[:y])
  end

  def to_direction(a, b)
    diff_x = a[:x] - b[:x]
    diff_y = b[:y] - a[:y]
    Math.atan2(diff_y, diff_x) - Math::PI
  end

  def draw_line(a, b, color = 0xff_ffffff)
    Gosu.draw_line(a[:x]/2, a[:y]/2, Gosu::Color.argb(color), b[:x]/2, b[:y]/2, Gosu::Color.argb(color), 1) if @enable_debug_line
  end

  def draw_point_rect(a, color = 0xff_ffffff)
    Gosu.draw_rect(a[:x] / 2 - 5, a[:y] / 2 - 5, 10, 10, Gosu::Color.argb(color), 2) if @enable_debug_line
  end
end
