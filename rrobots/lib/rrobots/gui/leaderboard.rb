class Leaderboard
  def initialize(window, robots, battlefield)
    @font_size = 24
    @robots = robots
    @battlefield = battlefield
    @font = Gosu::Font.new(window, 'Courier New', @font_size)
    @x_offset = @battlefield.width / 2 + @font_size
    @y_offset = @font_size * 2
  end

  def draw
    @font.draw("Tick #{@battlefield.time}", @x_offset, @font_size, ZOrder::UI, 1.0, 1.0, 0xffffffff)
    if @robots
      @robots.each_with_index do |r, i|
        y = @y_offset + i * @font_size
        @font.draw("#{r.first.name}", @x_offset, y, ZOrder::UI, 1.0, 1.0, r.last.font_color)
        @font.draw("#{r.first.energy.to_i}", @x_offset + (@font_size * 8), y, ZOrder::UI, 1.0, 1.0, r.last.font_color)
      end
    end
  end
end
