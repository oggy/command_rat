require 'spec_helper'
require 'command_rat/diff'

describe "Diff" do
  describe "#to_s" do
    it "should show just the headings if both sides are empty" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => '',
                                  :right_body => '')
      diff.to_s.should == "Left: | Right:\n"
    end

    it "should pad out to the length of the longest line" do
    end

    it "should pad correctly if the headings are the longest lines" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => "xxxxxxxx\n",
                                  :right_body => "xxxxxxxx\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:    | Right:
        |xxxxxxxx | xxxxxxxx
      EOS
    end

    it "should indicate lines that differ" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => "same\ndifferent\nsame\n",
                                  :right_body => "same\nnot same\nsame\n")
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
                                  :left_body => "one\ntwo\nthree\n",
                                  :right_body => "one\n")
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
                                  :left_body => "one\n",
                                  :right_body => "one\ntwo\nthree\n")
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
                                  :left_body => "one\ntwo",
                                  :right_body => "one\ntwo\n")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:               | Right:
        |one                 | one
        |two                 | two
        |No trailing newline <
      EOS
    end

    it "should show if the right doesn't end in a new line" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => "one\ntwo\n",
                                  :right_body => "one\ntwo")
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left: | Right:
        |one   | one
        |two   | two
        |      > No trailing newline
      EOS
    end

    it "should show the EOF indicators if given" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => "one\ntwo\n",
                                  :right_body => "one\ntwo\n",
                                  :left_eof => true,
                                  :right_eof => false)
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:        | Right:
        |one          | one
        |two          | two
        |EOF received X EOF not yet received
      EOS
    end

    it "should show the EOF indicators even if they're the same on both sides" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => "one\ntwo\n",
                                  :right_body => "one\ntwo\n",
                                  :left_eof => true,
                                  :right_eof => true)
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:        | Right:
        |one          | one
        |two          | two
        |EOF received | EOF received
      EOS
    end

    it "should comma-separate indicators if both are present" do
      diff = CommandRat::Diff.new(:left_heading => 'Left:',
                                  :right_heading => 'Right:',
                                  :left_body => "x",
                                  :right_body => '',
                                  :left_eof => true)
      diff.to_s.should == <<-EOS.gsub(/^ *\|/, '')
        |Left:                             | Right:
        |x                                 <
        |No trailing newline, EOF received <
      EOS
    end
  end
end
