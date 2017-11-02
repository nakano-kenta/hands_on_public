require 'rrobots'

module Coordinate
  def out_of_field?(point)
    point[:x] < 0 or point[:x] > battlefield_width or point[:y] < 0 or point[:y] > battlefield_height
  end

  def on_the_wall?(point)
    point[:x] < @size + 1 or point[:x] > battlefield_width - @size - 1 or point[:y] < @size + 1 or point[:y] > battlefield_height - @size - 1
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

class Kubota
  include Robot
  include Coordinate

  MAX_GUN_TURN = 45
  MAX_RADAR_TURN = 60
  MAX_TURN = 10
  MAX_SPEED = 8
  BULLET_SPPED = 30
  FIRE_POWR_RATIO = 3.3
  SAFETY_DISTANCE = 300
  def debug(*msg)
    p *msg if @debug_mode
  end

  def draw_gun_heading
    return unless @debug_mode and gui
    aiming_point = to_point gun_heading, 2000, position
    Gosu.draw_line(position[:x]/2,position[:y]/2,Gosu::Color.argb(0xff_ffffff),aiming_point[:x]/2,aiming_point[:y]/2,Gosu::Color.argb(0xff_ffffff),1)
  end

  def draw_anti_gravity_points
    return unless @debug_mode and gui
    @anti_gravity_points.each do |p|
      Gosu.draw_rect(p[:point][:x]/2-5,p[:point][:y]/2-5,10,10,Gosu::Color.argb(0xff_ffffff), 2)
    end
  end

  def draw_aiming_point(point)
    return unless @debug_mode and gui
    Gosu.draw_rect(point[:x]/2-10,point[:y]/2-10,20,20,Gosu::Color.argb(0xff_ffffff))
  end

  def draw_prospect_future(point)
    return unless @debug_mode and gui
    Gosu.draw_rect(point[:x]/2-1,point[:y]/2-1,2,2,Gosu::Color.argb(0xff_ffff00), 2)
  end

  def draw_destination
    return unless @debug_mode and gui
    Gosu.draw_rect(@destination[:x]/2-20,@destination[:y]/2-20,40,40,Gosu::Color.argb(0xff_00ff00))
  end

  def draw_bullets
    return unless @debug_mode and gui
    @enemy_bullets.each do |bullet|
      red = Gosu::Color.argb(0xff_ff0000)
      delta = to_point(bullet[:heading], BULLET_SPPED*8)
      p1 = add_point(bullet[:point], delta)
      p2 = diff_point(bullet[:point], delta)
      Gosu.draw_line(p1[:x]/2,p1[:y]/2,red,p2[:x]/2,p2[:y]/2,red, 1)
      Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,red)
    end

    @bullets.each do |bullet|
      blue = Gosu::Color.argb(0xff_0000ff)
      aqua = Gosu::Color.argb(0xff_00ffff)
      light_blue = Gosu::Color.argb(0xff_8888ff)
      if bullet[:aim_type] == :direct
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,blue)
      elsif bullet[:aim_type] == :accelerated
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,light_blue)
      elsif bullet[:aim_type] == :pattern
        Gosu.draw_rect(bullet[:point][:x]/2-3,bullet[:point][:y]/2-3,6,6,aqua)
      end
    end
  end

  def position
    @position ||= {x: x, y: y}
  end

  def set_destination(point)
    @destination = point
  end

  def max_turn(angle, max)
    [-max, [max, angle].min].max
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
    distance = [distance / 1000, 1].max
    [direction, alpha * [(1/distance) ** multi, 10].min]
  end

  WALL_AFFECT_DISTANCE = 200
  WALL_ALPHA = 0.7
  WALL_MULTI = 4
  ENEMY_AFFECT_DISTANCE = 800
  ENEMY_ALPHA = 1
  ENEMY_MULTI = 2
  BULLET_AFFECT_DISTANCE = 200
  BULLET_ALPHA = 5
  BULLET_MULTI = 2
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
      vectors << anti_gravity(bullet[:point], BULLET_AFFECT_DISTANCE, BULLET_ALPHA, BULLET_MULTI)
      10.times.each do |i|
        vectors << anti_gravity(to_point(bullet[:heading], BULLET_SPPED*(i+1) * 2, bullet[:point]), BULLET_AFFECT_DISTANCE, BULLET_ALPHA, BULLET_MULTI)
      end
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
      turn @turn_angle
      accelerate @acceleration
    end
  end

  def decide_move
    if @status == :lockon
      delta = {x: 0, y: 0}
      center_direction = to_direction(position, {x: battlefield_width/2, y: battlefield_height/2})
      if @lockon_target[:distance] > SAFETY_DISTANCE
        side_angle = 90
        side_angle = 110 if @lockon_target[:distance] > 500
        left = @lockon_target[:direction] - side_angle
        right = @lockon_target[:direction] + side_angle
        if diff_direction(left, center_direction).abs < diff_direction(right, center_direction).abs
          put_anti_gravity_point(0, to_point(right, 5, position), 100, 1, 1)
        else
          put_anti_gravity_point(0, to_point(left, 5, position), 100, 1, 1)
        end
      end
    end
    move_by_anti_gravity
  end

  def decide_scan
    towards_diff = diff_direction(radar_heading, @prev_radar_heading)
    if @status == :patrol
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
    elsif @status == :lockon
      if time - @lockon_start > 15
        set_patrol_mode
      end
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
    @prev_radar_heading = radar_heading
  end

  def prospect_next_by_acceleration(robot)
    return nil unless robot[:acceleration]
    speed = next_speed robot[:prospect_speed], robot[:acceleration][:speed]
    heading = robot[:prospect_heading] + robot[:acceleration][:heading]
    point = to_point heading, speed, robot[:prospect_point]
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

  PATTERN_LENGTH = 300
  PATTERN_CANDIDATES = 200
  PATTERN_OFFSET = 30
  def prospect_next_by_pattern(robot)
    if @replay_point == nil
      diff_by_past = {}
      PATTERN_CANDIDATES.times.each do |d|
        diff_by_past[d] = {
          index: @lockon_target[:logs].length - (PATTERN_OFFSET + d) - 1,
          past: (PATTERN_OFFSET + d),
          diff: 0,
          count: 0
        }
      end
      candidate_count = PATTERN_CANDIDATES
      @lockon_target[:logs].reverse.first(PATTERN_LENGTH).each_with_index do |log, rindex|
        if rindex < 30
        elsif rindex < 100
          next if rindex % 11 == 0
        else
          next if rindex % 33 == 0
        end
        index_offset = @lockon_target[:logs].length - rindex - PATTERN_OFFSET - 1
        PATTERN_CANDIDATES.times.each do |d|
          diff_obj = diff_by_past[d]
          next unless diff_obj
          break if candidate_count <= 1
          past_log = @lockon_target[:logs][index_offset - d]
          unless past_log and past_log[:acceleration] and log[:acceleration]
            if rindex < 30
              diff_by_past[d] = nil
              candidate_count -= 1
            end
            break if past_log
            next
          end
          if log[:acceleration][:speed].abs <= 1.5 and past_log[:acceleration][:speed].abs <= 1.5 and log[:acceleration][:heading].abs < MAX_TURN * 1.1 and past_log[:acceleration][:heading].abs < MAX_TURN * 1.1
            diff_by_past[d][:diff] += (log[:acceleration][:speed] - past_log[:acceleration][:speed]) ** 2
            diff_by_past[d][:diff] += diff_direction(log[:acceleration][:heading], past_log[:acceleration][:heading]) ** 2
            diff_by_past[d][:count] += 1
            if diff_by_past[d][:count] > 3 and (diff_by_past[d][:diff] / diff_by_past[d][:count].to_f) > 0.06
              diff_by_past[d] = nil
              candidate_count -= 1
            end
          end
        end
      end
      @replay_point = diff_by_past.values.compact.select{|a| a[:count] > 30}.min do |a, b|
        (a[:diff] / a[:count]) <=> (b[:diff] / b[:count])
      end
      @replay_point = false unless @replay_point
    end

    if @replay_point
      future_time = robot[:latest] - time + 1
      log = @lockon_target[:logs][@replay_point[:index] + future_time]
      ret = robot.dup
      if log
        ret[:acceleration] = log[:acceleration]
        return prospect_next_by_acceleration ret
      end
    end
    nil
  end

  def next_speed(current, acceleration)
    [[current + acceleration, 8].min, -8].max
  end

  def my_past_position
    @my_past_position
  end

  def my_future_position
    @my_future_position ||= to_point (heading + @turn_angle), next_speed(@speed, @acceleration), position
  end

  def fire_with_logging(n, robot)
    if @gun_heat == 0
      if @energy < 10
        if num_robots > 2 or !@lockon_target or @lockon_target[:energy] >= 0.3
          return if @energy < 1
        end
        n = [n, @energy / 2].min
      end
      fire n
      debug("Fire(#{n}) : #{robot[:aim_type]}")
      @bullets << {
        tick: time,
        start: position,
        robot: robot,
        point: to_point(gun_heading, BULLET_SPPED*3, position),
        heading: gun_heading,
        speed: BULLET_SPPED,
        aim_type: robot[:aim_type]
      }

      if robot[:aim_type] != :direct
        @bullets << {
          tick: time,
          start: position,
          robot: robot,
          point: to_point(@lockon_target[:direction], BULLET_SPPED*3, position),
          heading: @lockon_target[:direction],
          speed: BULLET_SPPED,
          aim_type: :direct
        }
      end
      if robot[:aim_type] != :acceleration
        target_future = calc_target_future do |target_future|
          prospect_next_by_acceleration target_future
        end
        if target_future
          direction = to_direction(position, target_future[:prospect_point])
          @bullets << {
            tick: time,
            start: position,
            robot: robot,
            point: to_point(direction, BULLET_SPPED*3, position),
            heading: direction,
            speed: BULLET_SPPED,
            aim_type: :accelerated
          }
        end
      end

      if robot[:aim_type] != :pattern
        target_future = calc_target_future do |target_future|
          prospect_next_by_pattern target_future
        end
        if target_future
          direction = to_direction(position, target_future[:prospect_point])
          @bullets << {
            tick: time,
            start: position,
            robot: robot,
            point: to_point(direction, BULLET_SPPED*3, position),
            heading: direction,
            speed: BULLET_SPPED,
            aim_type: :pattern
          }
        end
      end

      robot[:fire_logs] << {
        x: position[:x],
        y: position[:y],
        time: time
      }
    end
  end

  def calc_target_future(&block)
    target_future = @lockon_target
    prev_target_future = nil
    nearst = battlefield_height + battlefield_width
    ticks = 0
    100.times do
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
      if distance(aiming_point, target_future[:prospect_point]) < @size / 2
        draw_aiming_point(aiming_point)
        fire_with_logging [power, 3].min, @lockon_target
        set_patrol_mode
      end
      target_direction = to_direction(my_future_position, prospect_next_by_acceleration(target_future)[:prospect_point])
    end
    @turn_gun_angle = max_turn diff_direction(target_direction, gun_heading + @turn_angle), MAX_GUN_TURN
    turn_gun @turn_gun_angle
  end

  def decide_fire
    if @lockon_target and (time - @lockon_start) > 4
      log_by_aim_type = {}
      @lockon_target[:hit_logs].reverse.first(10).each do |hit_log|
        log_by_aim_type[hit_log[:aim_type]] ||= {
          aim_type: hit_log[:aim_type],
          hit: 0,
          miss: 0
        }
        log_by_aim_type[hit_log[:aim_type]][:hit] += hit_log[:hit].to_i
        log_by_aim_type[hit_log[:aim_type]][:miss] += hit_log[:miss].to_i
        log_by_aim_type[hit_log[:aim_type]][:ratio] = log_by_aim_type[hit_log[:aim_type]][:hit] / (log_by_aim_type[hit_log[:aim_type]][:hit] + log_by_aim_type[hit_log[:aim_type]][:miss]).to_f
      end
      highest_log = log_by_aim_type.values.max do |a, b|
        a[:ratio] <=> b[:ratio]
      end
      power = @lockon_target[:energy]/(FIRE_POWR_RATIO-0.01)
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
        @lockon_target[:aim_type] = [:direct, :accelerated, :pattern].shuffle.first
        power = [0.5, power].min
      end

      if num_robots == 2
        power = [power, @lockon_target[:energy]/(FIRE_POWR_RATIO+0.01)].min
        if @lockon_target[:energy] < 1 and energy > 8
          delta = {x: 0, y: 0}
          center_direction = to_direction(position, {x: battlefield_width/2, y: battlefield_height/2})
          side_angle = 120
          left = @lockon_target[:direction] - side_angle
          right = @lockon_target[:direction] + side_angle
          if diff_direction(left, center_direction).abs < diff_direction(right, center_direction).abs
            put_anti_gravity_point(2, to_point(right, 5, position), 100, 1000, 1)
          else
            put_anti_gravity_point(2, to_point(left, 5, position), 100, 1000, 1)
          end
          return
        end
      end

      if @lockon_target[:aim_type] == :pattern
        if @gun_heat > 0.2
          fire_or_turn power do |target_future|
            prospect_next_by_acceleration target_future
          end
        else
          fire_or_turn power do |target_future|
            prospect_next_by_pattern target_future
          end
        end
      elsif @lockon_target[:aim_type] == :accelerated
        fire_or_turn power do |target_future|
          prospect_next_by_acceleration target_future
        end
      elsif @lockon_target[:aim_type] == :direct
        aiming_point = to_point gun_heading, @lockon_target[:distance], position
        if distance(aiming_point, @lockon_target[:prospect_point]) < @size / 2
          fire_with_logging power, @lockon_target
          set_patrol_mode
        end
        target_direction = to_direction(my_future_position, @lockon_target[:prospect_point])
        @turn_gun_angle = max_turn diff_direction(target_direction, gun_heading + @turn_angle), MAX_GUN_TURN
        turn_gun @turn_gun_angle
      end
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
        fire_logs: [],
        hit_logs: [],
        got_hit_logs: [],
        logs: [],
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
        energy = scanned[:energy]
        robot[:speed] = speed
        robot[:heading] = heading
        robot[:prospect_speed] = speed
        robot[:prospect_heading] = heading
      end
      robot[:energy] = energy
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
      robot[:latest] = time
      robot[:hit] = 0
    end

    @robots.values.reject{|robot| robot[:latest] == time}.each do |robot|
      future = prospect_next_by_acceleration(robot)
      if future
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
      end
    end
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
            tick: robot[:latest],
            start: bullet_start,
            robot: robot,
            point: to_point(bullet_heading, BULLET_SPPED*4, bullet_start),
            heading: bullet_heading,
            speed: BULLET_SPPED,
            aim_type: :direct
          }

          my_context = {
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
          (robot[:distance] / BULLET_SPPED).to_i.times.each do
            my_context = prospect_next_by_acceleration(my_context)
          end
          bullet_heading = to_direction(bullet_start, my_context[:prospect_point])
          @enemy_bullets << {
            tick: robot[:latest],
            start: bullet_start,
            robot: robot,
            point: to_point(bullet_heading, BULLET_SPPED*4, bullet_start),
            heading: bullet_heading,
            speed: BULLET_SPPED,
            aim_type: :direct
          }

          if robot[:distance] > SAFETY_DISTANCE
            if SecureRandom.random_number < 0.5
              right = robot[:direction] + 90
              put_anti_gravity_point(16, to_point(right, 40, position), 300, 1, 1)
            else
              left = robot[:direction] - 90
              put_anti_gravity_point(16, to_point(left, 40, position), 300, 1, 1)
            end
          end
        end
      end
    end
  end

  def hit(events)
    events&.each do |hit|
      robot = @robots[hit[:to]]
      robot[:hit] = hit[:damage]
      bullet = @bullets.min do |a, b|
        distance(a[:point], robot[:prospect_point]) <=> distance(b[:point], robot[:prospect_point])
      end
      if bullet
        @bullets.reject!{|b| b == bullet}
        robot[:hit_logs] << {hit: 1, aim_type: bullet[:aim_type]}
      end
    end
  end

  def got_hit(events)
    # events&.each do |hit|
    #   robot = @robots[hit[:from]]
    #   bullet = @enemy_bullets.min do |a, b|
    #     distance(a[:point], position) <=> distance(b[:point], position)
    #   end
    #   if bullet
    #     @enemy_bullets.reject!{|b| b == bullet}
    #   end
    # end
  end

  def set_lockon_mode
    target = @robots.values.select{|a| time - a[:latest] <= 8}.sort{|a, b| a[:distance] <=> b[:distance] }.first
    if target
      if @lockon_target != target or @status != :lockon
        @lockon_target = target
        debug("lockon: #{@status} => #{@lockon_target[:name]} : #{@lockon_target[:aim_type]}")
        @lockon_start = time
        @status = :lockon
      end
    else
      set_patrol_mode
    end
  end

  def set_patrol_mode
    if num_robots <= 2 and @lockon_target and (time - @lockon_target[:latest]) < 3
      set_lockon_mode
    else
      @lockon_target = nil
      @patrol_tick = 0
      @status = :patrol
      @lockon_start = 0
    end
  end

  def move_bullets
    @bullets.select! do |bullet|
      bullet[:point] = to_point bullet[:heading], bullet[:speed], bullet[:point]
      robot = bullet[:robot]
      if distance(robot[:prospect_point], bullet[:point]) < @size
        bullet[:robot][:hit_logs] << {hit: 1, aim_type: bullet[:aim_type]}
        false
      elsif out_of_field?(bullet[:point])
        bullet[:robot][:hit_logs] << {miss: 1, aim_type: bullet[:aim_type]}
        false
      else
        true
      end
    end
    @enemy_bullets.select! do |bullet|
      bullet[:point] = to_point bullet[:heading], bullet[:speed], bullet[:point]
      if out_of_field?(bullet[:point])
        aim_type = :direct # TODO
        bullet[:robot][:got_hit_logs] << {miss: 1, aim_type: aim_type}
        false
      else
        true
      end
    end
  end

  def initial
    @debug_mode = false
    debug("gun: #{gun_heading}", "radar: #{radar_heading}")
    @turn_angle = 0
    @acceleration = 0
    @prev_radar_heading = radar_heading
    @robots = {}
    @bullets = []
    @enemy_bullets = []
    @anti_gravity_points = []
    @lockon_start = 0
    set_patrol_mode
  end

  def initial_for_tick events
    @my_future_position = nil
    @acceleration = 0
    @turn_angle = 0
    @turn_gun_angle = 0
    @replay_point = nil
    @position = nil
  end

  def tick events
    initial if time == 0
    initial_for_tick events

    if num_robots == 1
      @status = :win
      accelerate -speed
      turn MAX_TURN
      turn_gun MAX_GUN_TURN
      return
    end

    robot_scanned events['robot_scanned']
    move_bullets
    draw_gun_heading
    draw_bullets
    hit events['hit']
    got_hit events['got_hit']
    eval_enemy_bullet events['robot_scanned']
    decide_move
    do_move
    decide_fire
    decide_scan
    @my_past_position = position
    draw_destination
  end
end
