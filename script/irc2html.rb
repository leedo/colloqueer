#!/usr/bin/env ruby

require "enumerator"
require "cgi"

module Kernel
  def returning(value)
    yield value
    value
  end
end

class Regexp
  def uncapturize
    self.class.new(to_s.gsub(/(\A|[^\\])\(([^?])/, "\\1(?:\\2"))
  end
end

module Enumerable
  def in_groups_of(number, fill_with = nil, &block)
    if fill_with == false
      collection = self
    else
      padding = (number - size % number) % number
      collection = dup.concat([fill_with] * padding)
    end
  
    if block_given?
      collection.each_slice(number, &block)
    else
      returning [] do |groups|
        collection.each_slice(number) { |group| groups << group }
      end
    end
  end
end

module IrcFormatting
  BOLD      = "\002"
  COLOR     = "\003"
  RESET     = "\017"
  INVERSE   = "\026"
  UNDERLINE = "\037"
  
  COLOR_SEQUENCE  = /(\d{0,2})(?:,(\d{0,2}))?/
  FORMAT_SEQUENCE = /(
              #{BOLD}
            | #{COLOR}#{COLOR_SEQUENCE.uncapturize}?
            | #{RESET}
            | #{INVERSE}
            | #{UNDERLINE}
            )/x
  
  COLORS = %w( #fff #000 #008 #080 #f00 #800 #808 #f80
               #ff0 #0f0 #088 #0ff #00f #f0f #888 #ccc )
  
  class Formatting < Struct.new(:b, :i, :u, :fg, :bg)
    def dup
      self.class.new(*values)
    end
    
    def reset!
      self.b = self.i = self.u = self.fg = self.bg = nil
    end
    
    def accumulate(format_sequence)
      returning dup do |format|
        case format_sequence[/^./]
          when BOLD      then format.b = !format.b
          when UNDERLINE then format.u = !format.u
          when INVERSE   then format.i = !format.i
          when RESET     then format.reset!
          when COLOR     then format.fg, format.bg = extract_colors_from(format_sequence)
        end
      end
    end
    
    def to_css
      css_styles.map do |name, value|
        "#{name}: #{value}"
      end.join("; ")
    end
    
    protected
      def extract_colors_from(format_sequence)
        fg, bg = format_sequence[1..-1].scan(COLOR_SEQUENCE).flatten
        if fg.empty?
          [nil, nil]
        else
          [fg.to_i, bg ? bg.to_i : self.bg]
        end
      end

      def css_styles
        returning({}) do |styles|
          fg, bg = i ? [self.bg || 0, self.fg || 1] : [self.fg, self.bg]
          styles["color"] = COLORS[fg] if fg
          styles["background-color"] = COLORS[bg] if bg
          styles["font-weight"] = "bold" if b
          styles["text-decoration"] = "underline" if u
        end
      end
  end
  
  def self.parse_formatted_string(string)
    returning [""].concat(string.split(FORMAT_SEQUENCE)).in_groups_of(2) do |split_text|
      formatting = Formatting.new
      split_text.map! do |format_sequence, text|
        formatting = formatting.accumulate(format_sequence)
        [formatting, text]
      end
    end
  end
  
  def self.formatted_string_to_html(string)
    string.split("\n").map do |line|
      parse_formatted_string(line).map do |formatting, text|
        "<span style=\"#{formatting.to_css}\">#{CGI.escapeHTML(text || "")}</span>"
      end.join
    end.join("\n")
  end
end

if __FILE__ == $0
  puts "#{IrcFormatting.formatted_string_to_html($<.read)}"
end
