module CommandRat
  class Diff
    def initialize(params={})
      @left = side(params[:left_heading], params[:left])
      @right = side(params[:right_heading], params[:right])
    end

    def to_s
      string = "#{left[:heading].ljust(left[:width])} | #{right[:heading]}\n"
      (1...num_diff_lines).each do |i|
        left_line = side_line(left, i)
        right_line = side_line(right, i)
        separator = separator_between(left[:lines][i], right[:lines][i])
        string << "#{left_line.ljust(left[:width])}#{separator}#{right_line}\n"
      end
      string
    end

    private  # -------------------------------------------------------

    attr_reader :left, :right

    def side(heading, body)
      lines = [heading, *body.split(/\n/)]
      if body.length > 0 && body[-1] != ?\n
        lines << :'No trailing newline'
      end

      {
        :heading => heading,
        :lines => lines,
        :width => lines.map{|line| line.to_s.length}.max,
      }
    end

    def side_line(side, n)
      (side[:lines][n] || '').to_s
    end

    def separator_between(left, right)
      if left == right
        ' | '
      elsif left.nil?
        ' > '
      elsif right.nil?
        ' <'
      else
        ' X '
      end
    end

    def num_diff_lines
      [left[:lines].length, right[:lines].length].max
    end
  end
end
