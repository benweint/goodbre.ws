#!/usr/bin/env ruby

# TODO:
#   * Strip (partial) brewery names from beer names (e.g. great lakes big black smoke [great lakes brewing] -> big black smoke [great lakes brewing])
#   * Look for common 2-grams (splitting on word-boundaries)
#

require 'csv'
require 'pry'

class String
  def words
    split(/[\s-]+/)
  end

  def normalize(rules)
    normalized = self.dup
    rules.each do |rule, replacement|
      normalized.gsub!(rule, replacement)
    end
    normalized = normalized.tr(
      "ÀÁÂÃÄÅàáâãäåĀāĂăĄąÇçĆćĈĉĊċČčÐðĎďĐđÈÉÊËèéêëĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħÌÍÎÏìíîïĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľĿŀŁłÑñŃńŅņŇňŉŊŋÒÓÔÕÖØòóôõöøŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšſŢţŤťŦŧÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲųŴŵÝýÿŶŷŸŹźŻżŽž",
      "AAAAAAaaaaaaAaAaAaCcCcCcCcCcDdDdDdEEEEeeeeEeEeEeEeEeGgGgGgGgHhHhIIIIiiiiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnNnnNnOOOOOOooooooOoOoOoRrRrRrSsSsSsSssTtTtTtUUUUuuuuUuUuUuUuUuUuWwYyyYyYZzZzZz"
    )
    normalized.downcase!
    normalized
  end
end

def extract_word_frequencies(strings)
  freq = Hash.new(0)
  strings.uniq.each do |s|
    s.words.each { |w| freq[w] += 1 }
  end
  freq
end

class BeerComparator
  def initialize(old_beers, new_beers)
    old_beer_names = old_beers.map { |b| b[:name] }
    new_beer_names = new_beers.map { |b| b[:name] }
    old_brewery_names = old_beers.map { |b| b[:brewery] }
    new_brewery_names = new_beers.map { |b| b[:brewery] }
    @frequencies = {
      :name => {
        :old => extract_word_frequencies(old_beer_names),
        :new => extract_word_frequencies(new_beer_names)
      },
      :brewery => {
        :old => extract_word_frequencies(old_brewery_names),
        :new => extract_word_frequencies(new_brewery_names)
      }
    }
  end

  IGNORED_WORDS = ['', '-', '/', '+', 'and', 'the', 'of']

  def similarity(old_name, new_name, type)
    return 1.0 if old_name == new_name
    words_old = old_name.words - IGNORED_WORDS
    words_new = new_name.words - IGNORED_WORDS
    all_words = (words_old | words_new)
    common_words = (words_old & words_new)

    positive_score = 0
    common_words.each do |w|
      return 1.0 if @frequencies[type][:old][w] == 1 && @frequencies[type][:new][w] == 1
      average_frequency = (@frequencies[type][:old][w] + @frequencies[type][:new][w]) / 2.0
      positive_score += 1.0 / (average_frequency || 1.0)
    end
    positive_score /= all_words.size

    positive_score
  end

  def compare(old_beer, new_beer)
    name_score = similarity(old_beer[:name], new_beer[:name], :name)
    brewery_score = similarity(old_beer[:brewery], new_beer[:brewery], :brewery)
    if name_score == 0 || brewery_score == 0
      0.0
    else
      name_score + brewery_score
    end
  end
end

BREWERY_NORMALIZATION_RULES = {
  /'s(\b|$)/             => 's\1',
  /,/                    => '',
  /&/                    => ' and ',
  /\sCo\.?(\s|$)/          => '\1',
  /\sCompany\.?(\s|$)/     => '\1',
  /\sL\.?L\.?C\.?(\s|$)/   => '\1',
  /\sInc\.?(\s|$)/         => '\1',
  /\sltd\.?(\s|$)/i        => '\1',
  /\slimited(\s|$)/i       => '\1',
  /\sA\.?G\.?(\s|$)/i      => '\1',
  /\sS\.?A\.?(\s|$)/i      => '\1',
  /\sN\.?V\.?(\s|$)/i      => '\1',
  /\sB\.? ?V\.?(\s|$)/i    => '\1',
  /\sC\.?L\.?(\s|$)/i      => '\1',
  /\sA\.?\s?S\.?(\s|$)/i   => '\1',
  /\sGmbH(\s|$)/           => '\1',
  /\s\(samuel adams\)$/i   => '',
  /\s\/ bridgeport brewpub \+ bakery$/ => '',
}

BEER_NORMALIZATION_RULES = {}

def load_csv(path, headers)
  CSV.read(path).map { |row| Hash[headers.zip(row)] }
end

old_beers = load_csv("old_beers.csv", [:id, :name, :brewery_id, :brewery])
new_beers = load_csv("new_beers.csv", [:id, :name, :brewery_id, :brewery])
perfect_matches = []

old_beers.each do |b|
  b[:brewery] = b[:brewery].normalize(BREWERY_NORMALIZATION_RULES)
  b[:name] = b[:name].normalize(BEER_NORMALIZATION_RULES)
end
new_beers.each do |b|
  b[:brewery] = b[:brewery].normalize(BREWERY_NORMALIZATION_RULES)
  b[:name] = b[:name].normalize(BEER_NORMALIZATION_RULES)
end

comparator = BeerComparator.new(old_beers, new_beers)

if ARGV[0]
  old_beers = old_beers.select { |b| b[:name] =~ /#{ARGV[0]}/ || b[:brewery] =~ /#{ARGV[0]}/ }
end

comparison = Proc.new do |csv|
  old_beers.each do |old_beer|
    best_match = new_beers.max_by do |new_beer|
      comparator.compare(old_beer, new_beer)
    end
    score = comparator.compare(old_beer, best_match)

    if score > 0
      puts "[ #{score} ] #{old_beer[:name]} [#{old_beer[:brewery]}] -> #{best_match[:name]} [#{best_match[:brewery]}]"

      if score == 2.0 && csv
        csv << [old_beer[:id], best_match[:id]]
        old_beers.delete(old_beer)
        new_beers.delete(best_match)
      end
    else
      puts "[ no match ] #{old_beer[:name]} [#{old_beer[:brewery]}]"
    end
  end
end

CSV.open('perfect_matches', 'w+') do |csv|
  comparison.call(csv)
end

comparison.call(nil)
