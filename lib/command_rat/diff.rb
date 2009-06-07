module CommandRat
  class Diff
    def initialize(params={})
      @left = side(params[:left_heading], params[:left], params[:left_eof])
      @right = side(params[:right_heading], params[:right], params[:right_eof])
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

    def side(heading, body, eof)
      lines = [heading, *body.split(/\n/)]
      indicators = []
      if body.length > 0 && body[-1] != ?\n
        indicators << :'No trailing newline'
      end

      case eof
      when nil
      when true
        indicators << :'EOF received'
      when false
        indicators << :'EOF not yet received'
      end

      lines << indicators if !indicators.empty?

      {
        :heading => heading,
        :lines => lines,
        :width => lines.map{|line| display_line(line).length}.max,
      }
    end

    def side_line(side, n)
      display_line(side[:lines][n])
    end

    def display_line(raw_value)
      if raw_value.is_a?(Array)
        raw_value.join(', ')
      else
        raw_value || ''
      end
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
