# frozen_string_literal: true

class CreateLexiconImageDimensions < ActiveRecord::Migration[6.1]
  def change
    create_table :lexicon_image_dimensions do |t|
      t.integer :upload_id, null: false
      t.string :url, null: false
      t.integer :width, null: false
      t.integer :height, null: false
      t.float :aspect_ratio, null: false
      t.timestamps
    end

    add_index :lexicon_image_dimensions, :upload_id, unique: true
    add_index :lexicon_image_dimensions, :url
    add_foreign_key :lexicon_image_dimensions, :uploads, column: :upload_id, on_delete: :cascade
  end
end

