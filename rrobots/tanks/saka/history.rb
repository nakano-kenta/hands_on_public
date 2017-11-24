require 'rrobots'
require "#{File.dirname(__FILE__)}/utility"

module SakaUtil
  class History
    attr_accessor :x, :y, :energy, :fired
    def initialize(robot = {}, x = 0.0, y = 0.0)
      @energy = robot[:energy]
      @x, @y = x, y
      @fired = false
    end
    def distance_from(from)
      Math.hypot(self.x - from[:x], self.y - from[:y])
    end
    def [](key)
      return @x if key == :x
      return @y if key == :y
      return @energy if key == :energy
      nil
    end
  end

  class TargetHistory
    include Utility

    attr_reader :empty_count

    def initialize(owner, max)
      @owner = owner
      @max_histories = max
      @empty_count = 0
      @histories = []
      @selected = false
    end

    def selected?
      @selected
    end

    def selected=(is_selected)
      @selected = is_selected
    end

    def add(robot)
      new_x = Math::cos(robot[:direction].to_rad) * robot[:distance] + @owner.x
      new_y = -Math::sin(robot[:direction].to_rad) * robot[:distance] + @owner.y
      if @empty_count > 0 and !@histories.empty?
        from = @histories.last
        fo = {x: new_x, y: new_y}
        angle_rad = to_direction(from, to).to_rad
        speed = to_distance(from, to) / @empty_count
        [1..@empty_count].each do |pos|
          x = Math::cos(angle_rad) * speed * pos + from[:x],
          y = -Math::sin(angle_rad) * speed * pos + from[:y]
          @histories << History.new(robot, x, y)
        end
      end
      @empty_count = 0
      history = History.new(robot, new_x, new_y)
      @histories << history
      @histories.slice!(0, @histories.size - @max_histories) if @histories.size > @max_histories
      @next_histories = nil
      history
    end

    def next(generation)
      return @histories[generation - 1] if generation <= 0
      return @histories.last if @histories.size <= 1 or @empty_count > 0
      @next_histories ||= NextPositionStrategy.from_history @histories
      next_history = @next_histories.get_next(generation)
      History.new({}, next_history[:x], next_history[:y])
    end

    def add_empty()
      @empty_count += 1
    end

    def dump_histories()
      @histories.each do |history|
        debug_draw_point(history[:x] - 2, history[:y] - 2, 5, 0xffff0000)
      end
    end
    def dump_nexts()
      @next_histories.dump_nexts if @next_histories
    end
  end

  class NextPositionStrategy
    include SakaUtil::Utility
    include SakaUtil::Constants
    def self.from_history(histories)
      strategy = NextPositionStrategy.new(histories, true)
      strategy.append(6)
      strategy
    end
    def append(depth)
      return if depth <= 0 or @list.size < 2 or is_approx_empty?(0.05, 0.5)
      list = []
      @list.inject do |prev, cur|
        list << create_diff(prev, cur, @list.last, false)
        cur
      end
      @parent = NextPositionStrategy.new list
      @parent.append(depth - 1)
    end
    def dump_nexts
      (1..@next_start).each do |generation|
        history = get_next(generation)
        debug_draw_point(history[:x] - 2, history[:y] - 2, 5, 0xffffffff)
      end
    end
    def get_next(generation)
      return @list[@next_start - generation] if @next_start >= generation
      (@next_start...generation).each do |i|
        self.add_next
      end
      return @list.first
    end

    def add_next
      vec = get_next_vector
      from = @list.first
      direction = nearest_direction(vec[:direction], from[:direction])
      angle_rad = direction.to_rad
      distance = vec[:speed]
      distance = 0 if distance < 0
      distance = MAX_SPEED if distance > MAX_SPEED
      to = {
        x: Math::cos(angle_rad) * distance + from[:x],
        y: -Math::sin(angle_rad) * distance + from[:y]
      }
      diff = create_diff(to, from, @list.first, true)
      @list.insert(0, diff)
      @next_start += 1
      @parent&.append_next(@list[0], @list[1])
    end

    def get_next_vector(depth = 0)
      my_vec = {
        speed: @list.first[:speed],
        direction: @list.first[:direction]
      }
      if depth > 0
        sub_list = @list.slice(1, depth * 3)
        sub_list.each do |item|
          my_vec[:speed] += item[:speed]
          my_vec[:direction] += item[:direction]
        end
        my_vec[:speed] /= sub_list.size + 1
        my_vec[:direction] /= sub_list.size + 1
      end
      if @parent
        parent_vec = @parent.get_next_vector(depth + 1)
        if parent_vec
          my_vec[:speed] += parent_vec[:speed]
          my_vec[:direction] += parent_vec[:direction]
          return my_vec
        end
      end
      my_vec
    end

    def append_next(to, from)
      @list.insert(0, create_diff(to, from, @list.first,false))
      @next_start += 1
      @parent&.append_next(@list[0], @list[1])
    end

    def reset
      @list.slice!(0, @next_start)
      @next_start = 0
      @parent&.reset
    end

    private
    def is_approx_empty?(speed_diff, direction_diff)
      @list.inject do |prev, cur|
        diff_x, diff_y = prev[:x] - cur[:x], prev[:y] - cur[:y]
        if (prev[:speed] - cur[:speed]).abs > speed_diff \
          or (prev[:direction] - cur[:direction]).abs > direction_diff
          return false
        end
        cur
      end
      return true
    end
    def create_diff(to, from, last_entry, is_root)
      to_x, to_y = to[:x], to[:y]
      from_x, from_y = from[:x], from[:y]
      move_x, move_y = to_x - from_x, to_y - from_y
      if is_root
        direction = to_direction(from, to)
        if last_entry and last_entry[:direction]
          last_direction = last_entry[:direction]
          direction = nearest_direction(direction, last_direction)
        end
      else
        direction = nearest_direction(to[:direction], from[:direction]) - from[:direction]
      end
      {
        x: to_x,
        y: to_y,
        move_x: move_x,
        move_y: move_y,
        speed: is_root ? Math.hypot(move_x, move_y) : (to[:speed] - from[:speed]),
        direction: direction
      }
    end
    def initialize(listOrHistory, is_history = false)
      @list = listOrHistory
      @next_start = 0
      return unless is_history
      @list = []
      listOrHistory.reverse.inject do |prev, cur|
        break if cur.nil?
        @list << create_diff(prev, cur, @list.last, true)
        cur
      end
    end
  end
end
