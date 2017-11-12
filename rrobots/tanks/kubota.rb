require 'rrobots'

module Coordinate
  def out_of_field?(point)
    point[:x] < 0 or point[:x] > battlefield_width or point[:y] < 0 or point[:y] > battlefield_height
  end

  def from_wall(point)
    [
      [0, (point[:x] - @size)],
      [1, battlefield_width - @size - point[:x]],
      [2, (point[:y] - @size)],
      [3, battlefield_height - @size - point[:y]]
    ].min do |a, b|
      a[1] <=> b[1]
    end
  end

  def on_the_wall?(point, limit = 1)
    point[:x] < @size + limit or point[:x] > battlefield_width - @size - limit or point[:y] < @size + limit or point[:y] > battlefield_height - @size - limit
  end

  def angle_to_direction(angle)
    angle = angle % 360
    if angle > 180
      angle -= 360
    elsif angle < -180
      angle += 360
    end
    angle
  end

  def to_radian(angle)
    angle / 180.0 * Math::PI
  end

  def to_angle(radian)
    (radian * 180.0 / Math::PI + 360) % 360
  end

  def diff_direction(a, b)
    angle_to_direction(a - b)
  end

  def distance(a, b)
    Math.hypot(a[:x] - b[:x], a[:y] - b[:y])
  end

  def to_point(heading, distance, base = nil)
    radian = to_radian(heading)
    ret = {x: Math.cos(radian) * distance, y: - Math.sin(radian) * distance}
    ret = add_point(ret, base) if base
    ret
  end

  def add_point(a, b)
    {
      x: a[:x] + b[:x],
      y: a[:y] + b[:y]
    }
  end

  def diff_point(a, b)
    {
      x: a[:x] - b[:x],
      y: a[:y] - b[:y]
    }
  end

  def to_direction(a, b)
    diff_x = a[:x] - b[:x]
    diff_y = b[:y] - a[:y]
    to_angle(Math.atan2(diff_y, diff_x) - Math::PI)
  end

end

module Util
  MAX_GUN_TURN = 45.freeze
  MAX_RADAR_TURN = 60.freeze
  MAX_TURN = 10.freeze
  MAX_SPEED = 8.freeze
  BULLET_SPPED = 30.freeze
  FIRE_POWR_RATIO = 3.3.freeze
  HIT_RANGE = 40.freeze

  def reset_for_tick
    @my_future_position = nil
    @acceleration = 0
    @turn_angle = 0
    @turn_gun_angle = 0
    @position = nil
  end

  def position
    @position ||= {x: x, y: y}
  end

  def max_turn(angle, max)
    [-max, [max, angle].min].max
  end

  def center
    {x: battlefield_width, y: battlefield_height}
  end

  def left_or_right(towards, axis, &block)
    right = angle_to_direction(axis + 90)
    left = angle_to_direction(axis - 90)
    right_diff = diff_direction(right, towards)
    left_diff = diff_direction(left, towards)
    if right_diff.abs < left_diff.abs
      block.call right, right_diff
    else
      block.call left, left_diff
    end
  end

  def eval_wall(point)
    point[:x] = @size if point[:x] - @size < 0
    point[:y] = @size if point[:y] - @size < 0
    point[:x] = battlefield_width - @size if point[:x] + @size >= battlefield_width
    point[:y] = battlefield_height - @size if point[:y] + @size >= battlefield_height
    point
  end

  def next_speed(current, acceleration)
    [[current + acceleration, 8].min, -8].max
  end

  def reachable_distance(speed, tick)
    forward = speed
    back = speed
    distances = [0, 0]
    tick.times.each do
      forward = next_speed(forward, 1)
      back = next_speed(back, -1)
      distances[0] += forward
      distances[1] += back
    end
    distances
  end

  def my_past_position
    @my_past_position
  end

  def set_my_past_position
    @my_past_position = position
  end

  def my_future_position
    @my_future_position ||= to_point (heading + @turn_angle), next_speed(@speed, @acceleration), position
  end

  def new_my_context
    {
      latest: time,
      speed: @speed,
      heading: @heading,
      prospect_speed: @speed,
      prospect_heading: @heading,
      prospect_point: position,
      acceleration: {
        heading: @turn_angle,
        speed: @acceleration
      },
      logs: [],
    }
  end

end

class Kubota
  include Robot
  include Coordinate
  include Util

  SAFETY_DISTANCE = 500.freeze
  NUM_FIRE_LOGS = 200.freeze
  NUM_HIT_LOGS = 1000.freeze
  NUM_GOT_HIT_LOGS = 200.freeze
  NUM_LOGS = 1500.freeze
  DYING_ENERGY = 1.0.freeze

  def before_start
    @debug_msg = false
    @debug_move = false
    @debug_defence = false
    @debug_attack = false
  end

  def game_over
    debug "=== GAME OVER ==="
  end

  def tick events
    initial if time == 0
    initial_for_tick events

    robot_scanned events['robot_scanned']
    move_bullets
    move_enemy_bullets
    draw_gun_heading
    draw_enemy_bullets
    draw_bullets
    hit events['hit']
    got_hit events['got_hit']
    eval_enemy_bullet events['robot_scanned']
    decide_move
    do_move
    decide_fire
    decide_scan
    draw_destination
    set_my_past_position
  end

  def hit(events)
    events&.each do |hit|
      robot = @robots[hit[:to]]
      robot[:hit] = hit[:damage]
      bullet = @bullets.min do |a, b|
        distance(a[:point], robot[:prospect_point]) <=> distance(b[:point], robot[:prospect_point])
      end
      debug_attack("Hit #{bullet ? bullet[:aim_type] : :unknown}")
      if bullet
        @bullets.reject!{|b| b == bullet}
        robot[:hit_logs] << {hit: 1, aim_type: bullet[:aim_type], time: time}
        robot[:hit_logs] = robot[:hit_logs].last(NUM_HIT_LOGS)
      end
    end
  end

  def got_hit(events)
    events&.each do |hit|
      robot = @robots[hit[:from]]
      bullets = []
      @enemy_bullets.select! do |bullet|
        bullets << bullet if distance(bullet[:point], position) < HIT_RANGE * 1.5
      end
      if bullets.length > 0
        bullets.each do |bullet|
          debug_defence("got_hit(#{hit[:damage]}) #{hit[:from]}: #{bullet[:aim_type]}")
          robot[:got_hit_logs] << {
            time: time,
            bullet_type: bullet[:aim_type],
            hit: 1,
          }
          robot[:got_hit_logs] = robot[:got_hit_logs].last(NUM_GOT_HIT_LOGS)
        end
        @enemy_bullets.reject!{|b| bullets.include? b}
      else
        debug_defence("got_hit(#{hit[:damage]}) #{hit[:from]}: unknown")
        robot[:got_hit_logs] << {
          time: time,
          bullet_type: :unknown,
          hit: 1,
        }
        robot[:got_hit_logs] = robot[:got_hit_logs].last(NUM_GOT_HIT_LOGS)
      end
    end
  end

  private
  def debug(*msg)
    p "#{time}: #{msg.join ' '}" if @debug_msg
  end

  def debug_attack(*msg)
    p "#{time}: #{msg.join ' '}" if @debug_attack
  end

  def debug_defence(*msg)
    p "#{time}: #{msg.join ' '}" if @debug_defence
  end

  def draw_gun_heading
    return unless @debug_move and gui
    aiming_point = to_point gun_heading, 2000, position
    Gosu.draw_line(position[:x]/2,position[:y]/2,Gosu::Color.argb(0xff_ffffff),aiming_point[:x]/2,aiming_point[:y]/2,Gosu::Color.argb(0xff_ffffff),1)
  end

  def draw_anti_gravity_points
    return unless @debug_move and gui
    @anti_gravity_points.each do |p|
      Gosu.draw_rect(p[:point][:x]/2-5,p[:point][:y]/2-5,10,10,Gosu::Color.argb(0xff_ffffff), 2)
    end
  end

  def draw_aiming_point(point)
    return unless @debug_attack and gui
    Gosu.draw_rect(point[:x]/2-5,point[:y]/2-5,10,10,Gosu::Color.argb(0xff_ffffff), 3)
  end

  def draw_prospect_future(point)
    return unless @debug_attack and gui
    Gosu.draw_rect(point[:x]/2-1,point[:y]/2-1,2,2,Gosu::Color.argb(0xff_ffff00), 2)
  end

  def draw_destination
    return unless @debug_move and gui
    Gosu.draw_rect(@destination[:x]/2-20,@destination[:y]/2-20,40,40,Gosu::Color.argb(0xff_00ff00), 1)
  end

  def draw_enemy_bullets
    return unless @debug_defence and gui
    @enemy_bullets.each do |bullet|
      # TODO
      if bullet[:unknown]
        Gosu.draw_rect(bullet[:unknown][:x]/2-5,bullet[:unknown][:y]/2-5,10,10,Gosu::Color.argb(0xff_ff44ff), 3)
      end
      color = Gosu::Color.argb(0xff_4444ff)
      color = Gosu::Color.argb(0xff_ff4444) if bullet[:warning]
      delta = to_point(bullet[:heading], BULLET_SPPED*8)
      p1 = add_point(bullet[:point], delta)
      p2 = diff_point(bullet[:point], delta)
      Gosu.draw_line(p1[:x]/2,p1[:y]/2,color,p2[:x]/2,p2[:y]/2,color, 1)
      Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,color, 1)
    end
  end

  # TODO
  def draw_bullets
    return unless @debug_attack and gui
    @bullets.each do |bullet|
      direct = Gosu::Color.argb(0xff_000000)
      pattern = Gosu::Color.argb(0xff_88ffff)
      accelerated = Gosu::Color.argb(0xff_0000ff)
      simple = Gosu::Color.argb(0xff_00ff00)
      if bullet[:aim_type] == :direct
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,direct, 1)
      elsif bullet[:aim_type] == :accelerated
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,accelerated, 1)
      elsif bullet[:aim_type] == :pattern
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,pattern, 1)
      elsif bullet[:aim_type] == :simple
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,simple, 1)
      end
    end
  end

  def initial
    debug("gun: #{gun_heading}", "radar: #{radar_heading}")
    @turn_angle = 0
    @acceleration = 0
    @prev_radar_heading = radar_heading
    @durable_context[:robots] ||= {}
    @durable_context[:robots].each do |name, robot|
      robot[:latest] = 0
      robot[:energy] = 100
      robot[:prospect_point] = center
      robot[:acceleration] = nil
    end
    @robots = @durable_context[:robots]
    @bullets = []
    @enemy_bullets = []
    @anti_gravity_points = []
    @lockon_start = 0
    @lockon_target = nil
    set_patrol_mode
  end

  def initial_for_tick events
    reset_for_tick
    @lockon_start = 0 unless @status == :lockon
    @ram_attack_start = 0 unless @status == :ram_attack
    @log_by_aim_type_by_name = nil
  end

  def set_destination(point)
    point[:x] = @size + 1 if point[:x] <= @size + 1
    point[:x] = battlefield_width - @size - 1 if point[:x] >= battlefield_width - @size - 1
    point[:y] = @size + 1 if point[:y] <= @size + 1
    point[:y] = battlefield_height - @size - 1 if point[:y] >= battlefield_height - @size - 1

    @destination = point
  end

  def put_anti_gravity_point(tick, point, affect_distance = 200, alpha = 1, multi = 2)
    @anti_gravity_points << {
      point: point,
      expire: time + tick,
      affect_distance: affect_distance,
      alpha: alpha,
      multi: multi
    }
  end

  def anti_gravity(point, max_affect, alpha, multi)
    distance =  distance(position, point)
    return nil if distance > max_affect
    direction =  to_direction(point, position)
    distance = [distance / 100, 1].max
    [direction, alpha * [(1/distance) ** multi, 10].min]
  end

  WALL_AFFECT_DISTANCE = 200.freeze
  WALL_ALPHA = 10.freeze
  WALL_MULTI = 4.freeze
  ENEMY_AFFECT_DISTANCE = 500.freeze
  ENEMY_ALPHA = 10.freeze
  ENEMY_MULTI = 2.freeze
  BULLET_AFFECT_DISTANCE = 200.freeze
  BULLET_ALPHA = 50.freeze
  BULLET_MULTI = 2.freeze
  RAM_AFFECT_DISTANCE = 100.freeze
  RAM_ALPHA = 100.freeze
  RAM_MULTI = 1.freeze
  CLOSING_FOR_RAM_ALPHA = -1000.freeze
  CLOSING_FOR_RAM_MULTI = 0.freeze
  def move_by_anti_gravity_enemy_bullets(vectors, bullet)
    return unless bullet[:warning]
    10.times.each do |i|
      pair = anti_gravity(to_point(bullet[:heading], BULLET_SPPED*(i+1) * 2, bullet[:point]), BULLET_AFFECT_DISTANCE, BULLET_ALPHA, BULLET_MULTI)
      if pair
        right = bullet[:heading] + 90
        left = bullet[:heading] - 90
        right_diff = diff_direction(right, pair[0])
        left_diff = diff_direction(left, pair[0])
        if right_diff.abs < left_diff.abs
          pair[0] = right
          pair[1] *= Math.sin(to_radian(right_diff)).abs
        else
          pair[0] = left
          pair[1] *= Math.sin(to_radian(left_diff)).abs
        end
        vectors << pair
      end
    end
  end

  def move_by_anti_gravity
    vectors = []
    vectors << anti_gravity({x: 0, y: position[:y]}, WALL_AFFECT_DISTANCE, WALL_ALPHA, WALL_MULTI)
    vectors << anti_gravity({x: battlefield_width, y: position[:y]}, WALL_AFFECT_DISTANCE, WALL_ALPHA, WALL_MULTI)
    vectors << anti_gravity({x: position[:x], y: 0}, WALL_AFFECT_DISTANCE, WALL_ALPHA, WALL_MULTI)
    vectors << anti_gravity({x: position[:x], y: battlefield_height}, WALL_AFFECT_DISTANCE, WALL_ALPHA, WALL_MULTI)

    @robots.values.each do |robot|
      if (time - robot[:latest]) < 15
        vectors << anti_gravity(robot[:prospect_point], ENEMY_AFFECT_DISTANCE, ENEMY_ALPHA, ENEMY_MULTI)
      end
    end

    @enemy_bullets.each do |bullet|
      move_by_anti_gravity_enemy_bullets vectors, bullet
    end

    draw_anti_gravity_points
    @anti_gravity_points.select! do |p|
      vectors << anti_gravity(p[:point], p[:affect_distance], p[:alpha], p[:multi])
      p[:expire] > time
    end
    move_point = {x: 0, y: 0}
    vectors.compact.each do |vector|
      move_point = to_point(vector[0], vector[1], move_point)
    end
    set_destination(add_point(position, move_point))
  end

  def decide_move
    if @status == :ram_attack and (time - @ram_attack_start) > 80
      target = @robots.values.max{|a, b| a[:latest] <=> b[:latest] }
      set_destination(target[:prospect_point])
    else
      move_by_anti_gravity
    end
  end

  def decide_scan
    towards_diff = diff_direction(radar_heading, @prev_radar_heading)
    set_patrol_mode if @status == :lockon and time - @lockon_start > 15

    if @status == :lockon
      target_direction = to_direction(position, @lockon_target[:prospect_point])
      radar_diff = diff_direction(target_direction, radar_heading + @turn_angle + @turn_gun_angle)
      if radar_diff.abs < MAX_RADAR_TURN
        if radar_diff >= 0
          radar_diff += MAX_RADAR_TURN / 2
        else
          radar_diff -= MAX_RADAR_TURN / 2
        end
      end
      turn_radar radar_diff
    end

    if @status == :patrol or @status == :ram_attack
      if @patrol_tick % 8 <= 1
        turn_gun MAX_GUN_TURN
        turn_radar MAX_RADAR_TURN
      elsif @patrol_tick % 8 <= 5
        turn_gun -MAX_GUN_TURN
        turn_radar -MAX_RADAR_TURN
      elsif @patrol_tick % 8 <= 7
        turn_gun MAX_GUN_TURN
        turn_radar MAX_RADAR_TURN
      end
      @patrol_tick += 1
      if @robots.select {|_, robot| (time - robot[:latest]) < 8 }.length == (num_robots - 1)
        set_lockon_mode
      end
    end
    @prev_radar_heading = radar_heading
  end

  def aim_types
    [:direct, :accelerated, :pattern, :simple]
  end

  def virtual_bullet(robot, aim_type, &block)
    if robot[:aim_type] != aim_type
      target_future = calc_target_future do |target_future|
        block.call target_future
      end
      if target_future
        direction = to_direction(position, target_future[:prospect_point])
        @bullets << {
          time: time,
          start: position,
          robot: robot,
          point: to_point(direction, BULLET_SPPED*3, position),
          heading: direction,
          speed: BULLET_SPPED,
          aim_type: aim_type
        }
      end
    end
  end

  def fire_with_logging_virtual_bullets(robot)
    if robot[:aim_type] != :direct
      @bullets << {
        time: time,
        start: position,
        robot: robot,
        point: to_point(@lockon_target[:direction], BULLET_SPPED*3, position),
        heading: @lockon_target[:direction],
        speed: BULLET_SPPED,
        aim_type: :direct
      }
    end

    virtual_bullet robot, :accelerated do |target_future|
      prospect_next_by_acceleration target_future
    end
  end

  TOTALLY_HIT_RANGE = 240.freeze
  ZOMBI_ENERGY = 0.3.freeze
  def fire_with_logging(n, robot)
    if @gun_heat == 0
      if @energy < 10
        if @lockon_target and @lockon_target[:distance] < TOTALLY_HIT_RANGE
          n = 3
        else
          if num_robots > 2 or !@lockon_target or @lockon_target[:energy] >= ZOMBI_ENERGY
            return if @energy < 1
          end
          n = [n, @energy / 2].min
        end
      end
      fire n
      if @debug_attack
        log_by_aim_type = log_by_aim_type @lockon_target, 100
        line = "Fire(#{n}) : #{robot[:aim_type]}  [ "
        aim_types.each do |aim_type|
          log_by_aim_type[aim_type] ||= {hit: 0, ratio: 0}
          line += "#{aim_type}: #{log_by_aim_type[aim_type][:hit]}, "
        end
        line += ']'
        debug_attack line
      end

      @bullets << {
        time: time,
        start: position,
        robot: robot,
        point: to_point(gun_heading, BULLET_SPPED*3, position),
        heading: gun_heading,
        speed: BULLET_SPPED,
        aim_type: robot[:aim_type]
      }

      fire_with_logging_virtual_bullets(robot)

      robot[:fire_logs] << {
        point: robot[:prospect_point],
        speed: robot[:prospect_speed],
        heading: robot[:prospect_heading],
        acceleration: robot[:acceleration],
        position: my_future_position,
        time: time
      }
      robot[:fire_logs] = robot[:fire_logs].last NUM_FIRE_LOGS
    end
  end

  def calc_target_future(&block)
    target_future = @lockon_target
    prev_target_future = nil
    nearst = battlefield_height + battlefield_width
    ticks = 0
    (Math.hypot(battlefield_height, battlefield_width) / BULLET_SPPED).to_i.times do
      distance = distance(position, target_future[:prospect_point])
      if (distance - (BULLET_SPPED * ticks)).abs > nearst
        target_future = prev_target_future
        ticks -= 1
        break
      end
      prev_target_future = target_future
      nearst = (distance - (BULLET_SPPED * ticks)).abs
      target_future = block.call target_future
      break unless target_future
      draw_prospect_future(target_future[:prospect_point])
      ticks += 1
    end
    target_future
  end

  def fire_or_turn(power, &block)
    target_future = calc_target_future &block
    target_direction = @lockon_target[:direction]
    if target_future
      ticks = target_future[:latest] - time
      aiming_point = to_point gun_heading, BULLET_SPPED * ticks, position
      if distance(aiming_point, target_future[:prospect_point]) < HIT_RANGE
        draw_aiming_point(aiming_point)
        fire_with_logging [power, 3].min, @lockon_target
        set_patrol_mode
      end
      prospect = prospect_next_by_acceleration(target_future)
      target_direction = to_direction(my_future_position, prospect[:prospect_point])
    else
      debug_attack("Failure to prospect!! #{@status} #{@lockon_target[:aim_type]}")
    end
    @turn_gun_angle = max_turn diff_direction(target_direction, gun_heading + @turn_angle), MAX_GUN_TURN
    turn_gun @turn_gun_angle
  end

  def aim(power)
    aim_type = @lockon_target[:aim_type]
    if aim_type == :accelerated
      fire_or_turn power do |target_future|
        prospect_next_by_acceleration target_future
      end
      return aim_type
    elsif aim_type == :direct
      aiming_point = to_point gun_heading, @lockon_target[:distance], position
      if distance(aiming_point, @lockon_target[:prospect_point]) < HIT_RANGE
        fire_with_logging power, @lockon_target
        set_patrol_mode
      else
        target_direction = to_direction(my_future_position, @lockon_target[:prospect_point])
        @turn_gun_angle = max_turn diff_direction(target_direction, gun_heading + @turn_angle), MAX_GUN_TURN
        turn_gun @turn_gun_angle
      end
      return aim_type
    end
    nil
  end

  def decide_fire
    return unless @status == :lockon
    if @lockon_target and (time - @lockon_start) > 4
      power = (@lockon_target[:energy] + 0.1)/FIRE_POWR_RATIO
      if num_robots == 2
        if @lockon_target[:energy] < DYING_ENERGY
          if @lockon_target[:distance] > SAFETY_DISTANCE
            put_anti_gravity_point 0, @lockon_target[:prospect_point], battlefield_width + battlefield_height, CLOSING_FOR_RAM_ALPHA, CLOSING_FOR_RAM_MULTI
            return
          end
          return if @bullets.length > 0
        end
        if energy > 8 or @lockon_target[:energy] > ZOMBI_ENERGY
          power = [power, (@lockon_target[:energy] - 0.29) /FIRE_POWR_RATIO].min
        else
          power = [power, @lockon_target[:energy]/(FIRE_POWR_RATIO)].min
        end
      end

      highest_log = log_by_aim_type(@lockon_target, 100).values.max do |a, b|
        a[:ratio] <=> b[:ratio]
      end
      if highest_log and highest_log[:ratio] > 0
        @lockon_target[:aim_type] = highest_log[:aim_type]
        if highest_log[:hit] <= 2
          power = [0.5, power].min
        elsif highest_log[:ratio] <= 0.4
          power = [2, power].min
        elsif highest_log[:ratio] <= 0.2
          power = [1, power].min
        end
      else
        @lockon_target[:aim_type] = [:direct, :accelerated].shuffle.first
        power = [0.5, power].min
      end

      say "Aiming #{@lockon_target[:aim_type]}"
      aim power
    end
  end

  def log_by_aim_type(robot, n)
    return @log_by_aim_type_by_name[robot[:name]] if @log_by_aim_type_by_name and @log_by_aim_type_by_name[robot[:name]]
    @log_by_aim_type_by_name ||= {}
    log_by_aim_type = @log_by_aim_type_by_name[robot[:name]] ||= {}
    robot[:hit_logs].reverse.each do |hit_log|
      break if time - hit_log[:time] > n
      log_by_aim_type[hit_log[:aim_type]] ||= {
        aim_type: hit_log[:aim_type],
        hit: 0,
        miss: 0
      }
      log_by_aim_type[hit_log[:aim_type]][:hit] += hit_log[:hit].to_i
      log_by_aim_type[hit_log[:aim_type]][:miss] += hit_log[:miss].to_i
      log_by_aim_type[hit_log[:aim_type]][:ratio] = log_by_aim_type[hit_log[:aim_type]][:hit] / (log_by_aim_type[hit_log[:aim_type]][:hit] + log_by_aim_type[hit_log[:aim_type]][:miss]).to_f
    end
    log_by_aim_type
  end

  def prospect_next_by_acceleration(robot)
    return robot unless robot[:acceleration]
    speed = next_speed robot[:prospect_speed], robot[:acceleration][:speed]
    heading = robot[:prospect_heading] + robot[:acceleration][:heading]
    point = to_point heading, speed, robot[:prospect_point]
    eval_wall point
    {
      latest: robot[:latest] + 1,
      speed: speed,
      heading: heading,
      prospect_speed: speed,
      prospect_heading: heading,
      prospect_point: point,
      acceleration: robot[:acceleration],
      logs: [],
    }
  end

  def eval_enemy_bullet(events)
    events&.each do |scanned|
      robot = @robots[scanned[:name]]
      next unless robot[:acceleration]
      delta_energy = robot[:acceleration][:energy] + robot[:hit]
      robot[:hit] = 0
      if -0.1 > delta_energy and delta_energy >= -3
        crash = @robots.values.reject{|other| robot == other}.any? do |other|
          r = distance(robot[:prospect_point], other[:prospect_point]) < @size * 2.2
        end
        if !crash and !on_the_wall?(robot[:prospect_point]) or (robot[:acceleration][:speed].abs < 1 and robot[:prospect_speed].abs > 1)
          # Maybe shoot
          bullet_start = robot[:logs][-2][:prospect_point]
          bullet_heading = to_direction(bullet_start, my_past_position)
          @enemy_bullets << {
            time: robot[:latest],
            start: bullet_start,
            robot: robot,
            point: to_point(bullet_heading, BULLET_SPPED*3, bullet_start),
            heading: bullet_heading,
            speed: BULLET_SPPED,
            aim_type: :direct
          }
          my_context = new_my_context
          (robot[:distance] / BULLET_SPPED).to_i.times.each do
            my_context = prospect_next_by_acceleration(my_context)
          end
          bullet_heading = to_direction(bullet_start, my_context[:prospect_point])
          @enemy_bullets << {
            time: robot[:latest],
            start: bullet_start,
            robot: robot,
            point: to_point(bullet_heading, BULLET_SPPED*3, bullet_start),
            heading: bullet_heading,
            speed: BULLET_SPPED,
            aim_type: :accelerated
          }
        end
      end
    end
  end

  WARNING_BULLET_TICKS = 16.freeze
  UNKNOWN_BULLET_ALPHA = 10.freeze
  UNKNOWN_BULLET_MULTI = 1.freeze
  def move_enemy_bullets_bullet_type(robot, bullet, bullet_type_context)
    if bullet_type_context[:bullet_type] == :unknown
      if (distance(bullet[:point], position) / BULLET_SPPED) < WARNING_BULLET_TICKS
        robot[:direction]
        left_or_right @heading, robot[:direction] do |direction, diff|
          put_anti_gravity_point 0, to_point(direction, 50, position), battlefield_width + battlefield_height, UNKNOWN_BULLET_ALPHA, UNKNOWN_BULLET_MULTI
        end
      end
    elsif  bullet_type_context[:bullet_type] != bullet[:aim_type]
    # Do nothing
    else
      current_distance = battlefield_height + battlefield_width
      my_context = new_my_context
      bullet_point = bullet[:point]
      bullet[:warning] = false
      WARNING_BULLET_TICKS.times.each do
        d = distance(my_context[:prospect_point], bullet_point)
        if d < HIT_RANGE * 3
          bullet[:warning] = true
          break
        end
        break if current_distance < d
        current_distance = d
        my_context = prospect_next_by_acceleration(my_context)
        bullet_point = to_point bullet[:heading], bullet[:speed], bullet_point
      end
    end
  end

  def bullet_type_context(robot)
    context_by_bullet_type = {}
    recent_got_hits = []
    hit_count = 0
    robot[:got_hit_logs].reverse.each do |got_hit_log|
      hit_count += got_hit_log[:hit]
      recent_got_hits << got_hit_log
      break if hit_count >= 3
    end
    recent_got_hits.each do |got_hit_log|
      bullet_type = got_hit_log[:bullet_type]
      context_by_bullet_type[bullet_type] ||= {bullet_type: bullet_type, hit: 0, total: 0}
      context_by_bullet_type[bullet_type][:hit] += got_hit_log[:hit]
      context_by_bullet_type[bullet_type][:total] += 1.0
      context_by_bullet_type[bullet_type][:ratio] = context_by_bullet_type[bullet_type][:hit] / context_by_bullet_type[bullet_type][:total]
    end
    highest = context_by_bullet_type.values.max do |a, b|
      a[:ratio] <=> b[:ratio]
    end
    return highest if highest and highest[:hit] >= 2
    {bullet_type: :unknown, hit: recent_got_hits.length, total: recent_got_hits.length}
  end

  def move_enemy_bullets
    @bullet_type_context_by_name = {}
    @enemy_bullets.select! do |bullet|
      robot = bullet[:robot]
      landing_ticks = (distance(bullet[:start], position) / BULLET_SPPED)
      bullet[:point] = to_point bullet[:heading], bullet[:speed], bullet[:point]
      if !bullet[:miss] and distance(bullet[:point], position) < HIT_RANGE
        bullet[:miss] = 1
      end
      if out_of_field?(bullet[:point]) or (time - bullet[:time]) > landing_ticks
        if bullet[:miss]
          robot[:got_hit_logs] << {
            time: time,
            bullet_type: bullet[:aim_type],
            hit: 0,
          }
        end
        false
      else
        if @bullet_type_context_by_name[robot[:name]] == nil
          @bullet_type_context_by_name[robot[:name]] = {bullet_type: :unknown, hit: 0, total: 0}
          @bullet_type_context_by_name[robot[:name]] = bullet_type_context robot
          robot[:bullet_type] = @bullet_type_context_by_name[robot[:name]]
        end
        bullet_type_context = robot[:bullet_type]
        move_enemy_bullets_bullet_type robot, bullet, bullet_type_context
        true
      end
    end
  end

  def set_patrol_mode
    if num_robots <= 2 and @lockon_target and (time - @lockon_target[:latest]) < 3
      set_lockon_mode
    else
      @lockon_target = nil
      @patrol_tick = 0
      @status = :patrol
    end
  end

  def set_lockon_mode
    target = @robots.values.select{|a| time - a[:latest] <= 8}.sort{|a, b| a[:distance] <=> b[:distance] }.first
    if target
      if num_robots == 2 and target[:energy] < ZOMBI_ENERGY and energy > 8
        set_ram_attack_mode
      elsif @lockon_target != target or @status != :lockon
        @lockon_target = target
        debug_attack("lockon: #{@status} => #{@lockon_target[:name]} : #{@lockon_target[:aim_type]}")
        @lockon_start = time
        @status = :lockon
      end
    else
      set_patrol_mode
    end
  end

  def set_ram_attack_mode
    unless @status == :ram_attack
      @ram_attack_start = time
      debug_attack("ram_attack #{@status} => ram_attack")
      @status = :ram_attack
    end
  end

  def move_bullets
    @bullets.select! do |bullet|
      bullet[:point] = to_point bullet[:heading], bullet[:speed], bullet[:point]
      robot = bullet[:robot]
      if distance(robot[:prospect_point], bullet[:point]) < HIT_RANGE * 1.5
        robot[:hit_logs] << {hit: 1, aim_type: bullet[:aim_type], time: time}
        robot[:hit_logs] = robot[:hit_logs].last(NUM_HIT_LOGS)
        false
      elsif out_of_field?(bullet[:point])
        robot[:hit_logs] << {miss: 1, aim_type: bullet[:aim_type], time: time}
        robot[:hit_logs] = robot[:hit_logs].last(NUM_HIT_LOGS)
        false
      else
        true
      end
    end
  end

  def do_move
    if @destination
      direction = to_direction(position, @destination)
      diff = diff_direction(direction, heading)
      if diff.abs < 90
        @turn_angle = max_turn(diff, MAX_TURN)
        @acceleration = 1
      else
        @turn_angle = max_turn(angle_to_direction(diff + 180), MAX_TURN)
        @acceleration = -1
      end

      if @status == :lockon and num_robots == 2
        if @lockon_target[:distance] > SAFETY_DISTANCE
          left_or_right (@heading + @turn_angle), @lockon_target[:direction] do |direction, diff|
            @turn_angle += diff / 5
          end
        end
      end

      if on_the_wall? position, 50
        current = from_wall(position)
        if current[1] > from_wall(my_future_position)[1]
          if [0, 1].include? current[0]
            left_or_right @heading, 0 do |direction, diff|
              @turn_angle = diff
            end
          else
            left_or_right @heading, 90 do |direction, diff|
              @turn_angle = diff
            end
          end
        end
      end

      turn @turn_angle
      accelerate @acceleration
    end
  end

  def robot_scanned(events)
    return if @robot_scanned_time == time
    @robot_scanned_time = time
    events&.each do |scanned|
      point = to_point scanned[:direction], scanned[:distance], position
      @robots[scanned[:name]] ||= {
        name: scanned[:name],
        aim_type: :accelerated,
        bullet_type: :unknown,
        fire_logs: [],
        hit_logs: [],
        got_hit_logs: [],
        logs: [],
        statistics: [],
      }
      robot = @robots[scanned[:name]]
      if robot[:latest]
        diff = distance(robot[:point], point)
        speed = diff / (time - robot[:latest])
        heading = to_direction(robot[:point], point)
        if robot[:speed]
          robot[:acceleration] = {
            speed: (speed - robot[:speed]) / (time - robot[:latest]),
            heading: diff_direction(heading, robot[:heading]) / (time - robot[:latest]),
            energy: scanned[:energy] - robot[:energy]
          }
        end
        robot[:speed] = speed
        robot[:heading] = heading
        robot[:prospect_speed] = speed
        robot[:prospect_heading] = heading
      end
      robot[:energy] = scanned[:energy]
      robot[:distance] = scanned[:distance]
      robot[:direction] = scanned[:direction]
      robot[:point] = point
      robot[:prospect_point] = point
      robot[:logs] << {
        time: time,
        prospect_heading: robot[:prospect_heading],
        prospect_speed: robot[:prospect_speed],
        prospect_point: point,
        acceleration: robot[:acceleration],
      }
      robot[:fire_logs].reverse.each do |fire_log|
        diff_ticks = time - fire_log[:time]
        if (diff_ticks * BULLET_SPPED - scanned[:distance]).abs < HIT_RANGE * 1.1
          robot[:statistics] << {
            time: fire_log[:time],
            prospect_heading: robot[:prospect_heading],
            prospect_speed: robot[:prospect_speed],
            acceleration: robot[:acceleration],
            heading: to_direction(fire_log[:point], robot[:prospect_point]),
            speed: distance(fire_log[:point], robot[:prospect_point]) / diff_ticks
          }
          break
        end
        break if diff_ticks * BULLET_SPPED > scanned[:distance]
      end

      robot[:logs] = robot[:logs].last(NUM_LOGS)
      robot[:latest] = time
      robot[:hit] = 0
    end

    @robots.values.reject{|robot| robot[:latest] == time}.each do |robot|
      future = prospect_next_by_acceleration(robot)
      robot[:prospect_speed] = future[:prospect_speed]
      robot[:prospect_heading] = future[:prospect_heading]
      robot[:prospect_point] = future[:prospect_point]
      robot[:logs] << {
        time: time,
        prospect_heading: future[:prospect_heading],
        prospect_speed: future[:prospect_speed],
        prospect_point: future[:prospect_point],
        acceleration: future[:acceleration]&.dup,
      }
      robot[:logs] = robot[:logs].last(NUM_LOGS)
    end
  end
end
