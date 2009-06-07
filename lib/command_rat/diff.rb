module CommandRat
  class Diff
    def initialize(params={})
      @left = Side.new(params[:left_heading], params[:left_body], params[:left_eof])
      @right = Side.new(params[:right_heading], params[:right_body], params[:right_eof])
    end

    def to_s
      string = "#{left.heading.ljust(left.width)} | #{right.heading}\n"
      (1...num_lines).each do |i|
        left_line = left.display_line(i).ljust(left.width)
        separator = separator_between(left.raw_line(i), right.raw_line(i))
        right_line = right.display_line(i)
        string << "#{left_line}#{separator}#{right_line}\n"
      end
      string
    end

    private  # -------------------------------------------------------

    attr_reader :left, :right

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

    def num_lines
      [left.num_lines, right.num_lines].max
    end

    class Side
      def initialize(heading, body, eof)
        @heading = heading
        @lines = [heading, *body.split(/\n/)]

        indicators = []
        if body.length > 0 && body[-1] != ?\n
          indicators << :'No trailing newline'
        end

        if eof == true
          indicators << :'EOF received'
        elsif eof == false
          indicators << :'EOF not yet received'
        end
        @lines << indicators if !indicators.empty?
      end

      attr_reader :heading, :lines, :width

      def width
        @width ||= (0...num_lines).map{|i| display_line(i).length}.max
      end

      def raw_line(num)
        @lines[num]
      end

      def display_line(num)
        raw = raw_line(num)
        if raw.is_a?(Array)
          raw.join(', ')
        else
          raw || ''
        end
      end

      def num_lines
        @lines.length
      end
    end
  end
end
