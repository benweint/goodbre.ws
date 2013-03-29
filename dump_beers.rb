#!/usr/bin/env ruby 

require 'csv'

$redis = Recommendable.redis

def fetch_old_rated_beers
  old_beers = []
  OldBeer.find_each do |beer|
    liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(Beer, beer.id)
    disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(Beer, beer.id)
    old_beers << beer if $redis.scard(liked_by_set) > 0 || $redis.scard(disliked_by_set) > 0
  end
  old_beers
end

if $redis.scard('rated_old_beers') > 0
  rated_beer_ids = $redis.smembers('rated_old_beers')
else
  rated_beer_ids = fetch_old_rated_beers.map(&:id)
  puts "Caching IDs of #{rated_beer_ids.size} rated old beers"
  $redis.sadd('rated_old_beers', rated_beer_ids)
end
puts "Found #{rated_beer_ids.size} rated beers"

rated_beers = OldBeer.where("id IN (?)", rated_beer_ids)

CSV.open("old_beers.csv", "wb") do |csv|
  rated_beers.each do |beer|
    csv << [beer.id, beer.name, beer.brewery_id, beer.brewery.name]
  end
end

CSV.open("new_beers.csv", "wb") do |csv|
  Beer.find_each do |beer|
    beer.breweries.each do |brewery|
      csv << [beer.id, beer.name, brewery.id, brewery.name]
    end
  end
end
