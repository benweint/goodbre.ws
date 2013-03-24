class OldBrewery < ActiveRecord::Base
  include Permalinkable
  include Socialable

  self.table_name = :breweries

  establish_connection(:old)

  has_many :beers, :class_name => 'OldBeer', :foreign_key => 'brewery_id'
  has_and_belongs_to_many :guilds
  has_many :locations

  def self.paginate(options = {})
    page(options[:page]).per(options[:per_page])
  end
end
