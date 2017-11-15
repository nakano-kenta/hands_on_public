class Leaderboard
  def initialize(window, robots, battlefield)
    @font_size = 24
    @robots = robots
    @battlefield = battlefield
    @font = Gosu::Font.new(window, 'Courier New', @font_size)
    @x_offset = @battlefield.width / 2 + @font_size / 2
    @y_offset = @font_size * 2
  end

  def draw
    @font.draw("Tick #{@battlefield.time}", @x_offset, @font_size, ZOrder::UI, 1.0, 1.0, 0xffffffff)
    if @robots
      @robots.each_with_index do |r, i|
        color = r.last.font_color
        color = color & 0x4fffffff if r.first.dead
        i *= 2
        y = @y_offset + i * @font_size
        @font.draw("#{r.first.uniq_name}", @x_offset, y, ZOrder::UI, 1.0, 1.0, color)
        @font.draw("#{r.first.energy.to_i}", @x_offset + (@font_size * 8), y, ZOrder::UI, 1.0, 1.0, color)
        y = @y_offset + (i+1) * @font_size
        @font.draw("k:#{r.first.kills}", @x_offset + (@font_size*0.5), y, ZOrder::UI, 1.0, 1.0, color)
        @font.draw("d:#{'%.2f' % r.first.damage_given}", @x_offset + (@font_size*2.5), y, ZOrder::UI, 1.0, 1.0, color)
        @font.draw("h:#{r.first.num_hit}", @x_offset + (@font_size) * 7, y, ZOrder::UI, 1.0, 1.0, color)
      end
    end
  end
end
