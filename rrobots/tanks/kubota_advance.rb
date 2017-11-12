require "#{File.dirname(__FILE__)}/kubota"

class KubotaAdvance < Kubota
  PATTERN_LENGTH = 300.freeze
  PATTERN_CANDIDATES = 200.freeze
  PATTERN_OFFSET = 30.freeze

  def before_start
    super
    body_color 'red'
    radar_color 'red'
    turret_color 'red'
    font_color 'red'
    @debug_msg = false
    @debug_move = false
    @debug_defence = false
    @debug_attack = false
  end

  def game_over
    super
    @robots.each do |name, robot|
      log_by_aim_type = log_by_aim_type robot, 50000
      line = "#{name}: [ "
      log_by_aim_type.each do |aim_type, log|
        line += "#{aim_type}: #{log[:hit]} / #{log[:hit] + log[:miss]} (#{(log[:ratio] * 10000).to_i/100.0}%), "
      end
      debug line
    end
  end

  def tick events
    super
  end

  private
  RANDOM_AVOIDANCE_ALPHA = -100.freeze
  RANDOM_AVOIDANCE_MULTI = 0.freeze

  def move_by_anti_gravity_enemy_bullets(vectors, bullet)
    if bullet[:unknown]
      vectors << anti_gravity(bullet[:unknown], battlefield_height + battlefield_width, RANDOM_AVOIDANCE_ALPHA, RANDOM_AVOIDANCE_MULTI)
    else
      super
    end
  end

  def prospect_next_by_pattern(robot)
    if @replay_point == nil
      diff_by_past = {}
      PATTERN_CANDIDATES.times.each do |d|
        diff_by_past[d] = {
          index: @lockon_target[:logs].length - (PATTERN_OFFSET + d) - 1,
          past: (PATTERN_OFFSET + d),
          diff: 0,
          count: 0,
          d: d
        }
      end
      candidate_count = PATTERN_CANDIDATES
      @lockon_target[:logs].reverse.first(PATTERN_LENGTH).each_with_index do |log, rindex|
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
          diff_by_past[d][:diff] += (log[:acceleration][:speed] - past_log[:acceleration][:speed]) ** 2
          diff_by_past[d][:diff] += diff_direction(log[:acceleration][:heading], past_log[:acceleration][:heading]) ** 2
          diff_by_past[d][:count] += 1
        end
        if rindex > (PATTERN_LENGTH / 6)
          sorted = diff_by_past.values.select{|a| a and a[:count] > 0}.sort{|a, b| (a[:diff] / a[:count]) <=> (b[:diff] / b[:count])}
          sorted.reverse.first((sorted.length * (0.5 - 0.5 * (PATTERN_LENGTH - rindex) / PATTERN_LENGTH)).to_i).each do |diff|
            diff_by_past[diff[:d]] = nil
            candidate_count -= 1
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
      log ||= @lockon_target[:logs][@replay_point[:index] + (future_time % @replay_point[:past])]
      if log
        ret = robot.dup
        ret[:acceleration] = log[:acceleration]
        return prospect_next_by_acceleration ret
      end
    else
      return prospect_next_by_acceleration robot
    end
  end

  def prospect_next_by_simple(robot)
    return prospect_next_by_acceleration(robot) if !robot[:statistics] or !robot[:acceleration]
    if @nearst_log == nil
      acceleration = {}
      @nearst_log = robot[:statistics].min do |a, b|
        diff_a = (robot[:speed] - a[:speed]) ** 2 + (robot[:speed] - a[:acceleration][:speed]) ** 2 + (robot[:acceleration][:heading] - a[:acceleration][:heading]) ** 2
        diff_b = (robot[:speed] - b[:speed]) ** 2 + (robot[:speed] - b[:acceleration][:speed]) ** 2 + (robot[:acceleration][:heading] - b[:acceleration][:heading]) ** 2
        diff_a <=> diff_b
      end
    end
    return prospect_next_by_acceleration(robot) unless @nearst_log
    diff_heading = diff_direction(@nearst_log[:prospect_heading], robot[:prospect_heading])
    target_future = {
      latest: robot[:latest],
      speed: @nearst_log[:speed],
      heading: (@nearst_log[:heading] - diff_heading),
      prospect_speed: @nearst_log[:speed],
      prospect_heading: (@nearst_log[:heading] - diff_heading),
      prospect_point: robot[:prospect_point],
      acceleration: { speed: 0, heading: 0 },
      logs: [],
    }
    return prospect_next_by_acceleration(target_future)
  end

  def fire_with_logging_virtual_bullets(robot)
    super

    virtual_bullet robot, :pattern do |target_future|
      prospect_next_by_pattern target_future
    end

    virtual_bullet robot, :simple do |target_future|
      prospect_next_by_simple target_future
    end
  end

  def aim(power)
    aim_type = @lockon_target[:aim_type]
    if aim_type == :simple
      fire_or_turn power do |target_future|
        prospect_next_by_simple target_future
      end
      return aim_type
    else
      return if super(power)
      if aim_type == :pattern
        if @gun_heat > 0.2
          fire_or_turn power do |target_future|
            prospect_next_by_acceleration target_future
          end
        else
          fire_or_turn power do |target_future|
            prospect_next_by_pattern target_future
          end
        end
        return aim_type
      end
    end
    nil
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
    return highest if highest and highest[:hit] >= 2 and highest[:ratio] > 0.5
    {bullet_type: :unknown, hit: recent_got_hits.length, total: recent_got_hits.length}
  end

  def move_enemy_bullets_bullet_type(robot, bullet, bullet_type_context)
    # TODO
    # if bullet_type_context[:total] < 5
    #   bullet_type_context[:bullet_type] = :unknown
    # elsif (1.0 * bullet_type_context[:hit] / bullet_type_context[:total]) <= 0.5
    #   bullet_type_context[:bullet_type] = :unknown
    # end
    if bullet_type_context[:bullet_type] == :unknown
      robot[:unknown_bullet] = bullet if !robot[:unknown_bullet] or !robot[:unknown_bullet][:unknown]
    else
      super
    end
  end

  def random_by_slope(slope)
    random = 0
    count = slope
    while count > 0
      count -= 1.0
      alpha = 1.0
      if slope < 0
        alpha = count + 1.0
      end
      random += alpha * SecureRandom.random_number
    end
    random = 0.5 - (random / slope - 0.5).abs
    0.5 + ((SecureRandom.random_number < 0.5) ? random : -random)
  end

  def move_enemy_bullets
    super
    # TODO: move to where ?
    @robots.each do |name, robot|
      if robot[:unknown_bullet] and !robot[:unknown_bullet][:unknown]
        bullet = robot[:unknown_bullet]
        landing_ticks = distance(bullet[:point], position) / BULLET_SPPED
        bullet_direction = to_direction(position, bullet[:start])
        move_direction = bullet_direction + 90
        ticks = landing_ticks.to_i
        forward, backward = reachable_distance(speed, ticks)
        diff_turn = diff_direction(heading, move_direction)
        turn_towards = (diff_turn.abs < 90) ? 1 : -1
        from = to_point(move_direction, forward*turn_towards, position)
        to = to_point(move_direction, backward*turn_towards, position)
        eval_wall from
        eval_wall to
        slope = 1 + (50.0 / landing_ticks)
        random = random_by_slope slope
        # random = (SecureRandom.random_number < 0.5) ? 1.0 : 0
        bullet[:unknown] = {
          x: ((to[:x] - from[:x]) * random + from[:x]),
          y: ((to[:y] - from[:y]) * random + from[:y]),
        }
      end
    end
  end

  def initial
    super
  end

  COLORS = ['white', 'blue', 'yellow', 'red', 'lime'].freeze
  def initial_for_tick events
    super
    color = COLORS[(time / 5) % COLORS.size]
    body_color color
    radar_color color
    turret_color color
    font_color color

    @replay_point = nil
    @nearst_log = nil
    @robots.values.each do |robot|
      robot[:unknown_bullet] = nil
    end
  end
end
