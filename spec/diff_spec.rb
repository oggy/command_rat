require 'spec_helper'
require 'command_rat/diff'

describe "Diff" do
  describe "#to_s" do
    it "should show just the headings if both sides are empty" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => '',
                                  :right => '')
      diff.to_s.should == "Left: | Right:\n"
    end

    it "should pad out to the length of the longest line" do
    end

    it "should pad correctly if the headings are the longest lines" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => "xxxxxxxx\n",
                                  :right => "xxxxxxxx\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:    | Right:
        |xxxxxxxx | xxxxxxxx
      EOS
    end

    it "should indicate lines that differ" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => "same\ndifferent\nsame\n",
                                  :right => "same\nnot same\nsame\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:     | Right:
        |same      | same
        |different X not same
        |same      | same
      EOS
    end

    it "should indicate lines that are only on the left" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => "one\ntwo\nthree\n",
                                  :right => "one\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left: | Right:
        |one   | one
        |two   <
        |three <
      EOS
    end

    it "should indicate lines that are only on the right" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => "one\n",
                                  :right => "one\ntwo\nthree\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left: | Right:
        |one   | one
        |      > two
        |      > three
      EOS
    end

    it "should show if the left doesn't end in a new line" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => "one\ntwo",
                                  :right => "one\ntwo\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:             | Right:
        |one               | one
        |two               | two
        |No newline at EOF <
      EOS
    end

    it "should show if the right doesn't end in a new line" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left => "one\ntwo\n",
                                  :right => "one\ntwo")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left: | Right:
        |one   | one
        |two   | two
        |      > No newline at EOF
      EOS
    end
  end
end
