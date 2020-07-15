#!/usr/bin/ruby
# coding: utf-8
require 'erb'
require 'set'

RUST_FILE = "../src/autogen_hsk.rs"
HSK1 = {src: "hsk1.tsv", qc: "hsk1-QC-do-not-edit.tsv"}
HSK2 = {src: "hsk2.tsv", qc: "hsk2-QC-do-not-edit.tsv"}

# Returns array: [[hanzi, pinyin], [hanzi, pinyin], ...]
def read_tsv(file)
  File.read(file).lines.map { |n| n.chomp.split("\t") }
end

# Make a set with each unique character used in pinyin from <file>.
def char_set(file)
  Set.new(read_tsv(file).map { |_, pinyin| pinyin.downcase.chars }.flatten)
end

# Normalize pinyin to lowercase ASCII (remove diacritics/whitespace/punctuation).
TR_FROM = " 'abcdefghijklmnopqrstuwxyzàáèéìíòóùúāēěīōūǎǐǒǔǚ"
TR_TO   = " 'abcdefghijklmnopqrstuwxyzaaeeiioouuaeeiouaiouv"
ELIDE   = " '"
def normalize(pinyin)
  n = pinyin.downcase.delete(ELIDE).tr(TR_FROM, TR_TO)
  abort "Error: normalize(#{pinyin}) gave #{n} (non-ascii). Check TR_FROM & TR_TO." if !n.ascii_only?
  return n
end

# Check integrity and coverage of the character transposition table
detected = (char_set(HSK1[:src]) + char_set(HSK2[:src])).to_a.sort.join("")
if detected != TR_FROM
  warn "Error: Characters used in pinyin of #{HSK1[:src]} or #{HSK2[:src]} do not match TR_FROM"
  warn " detected: \"#{detected}\""
  warn " TR_FROM:  \"#{TR_FROM}\""
  abort "You need to update TR_FROM and TR_TO so pinyin will properly normalized to ASCII"
end
abort "Error: Check for TR_FROM/TR_TO length mismatch" if TR_FROM.size != TR_TO.size

# Generate a quality check TSV file for manually checking the normalized pinyin
print "This will overwrite #{HSK1[:qc]}, #{HSK2[:qc]}, and #{RUST_FILE}\nProceed? [y/N]: "
abort "no changes made" if !["y", "Y"].include? gets.chomp
for h in [HSK1, HSK2]
  File.open(h[:qc], "w") { |qc|
    for hanzi, pinyin in read_tsv(h[:src])
      qc.puts "#{hanzi}\t#{pinyin}\t#{normalize(pinyin)}"
    end
  }
end

# Merge hanzi values for duplicate pinyin search keys
# example: ["he", "he"] and ["喝", "和"] get turned into ["he"] and ["喝\t和"]
merged_hanzi = []
merged_pinyin = []
first_index_of = {}
duplicate_pinyin = []
i = 0
for level in [HSK1, HSK2]
  for hanzi, pinyin in read_tsv(level[:src])
    nrmlzd_pinyin = normalize(pinyin)
    if first_index_of[nrmlzd_pinyin]
      # Duplicate search key ==> Append hanzi to first entry
      merged_hanzi[first_index_of[nrmlzd_pinyin]] += "\t#{hanzi}"
      duplicate_pinyin << nrmlzd_pinyin
    else
      # First instance of search key ==> Add new entries
      merged_hanzi[i] = hanzi
      merged_pinyin[i] = nrmlzd_pinyin
      first_index_of[nrmlzd_pinyin] = i
      i += 1
    end
  end
end

# Generate rust source code with hanzi and pinyin arrays
File.open(RUST_FILE, "w") { |rf|
  TEMPLATE = <<~RUST
    // This file is automatically generated. DO NOT MAKE EDITS HERE!
    // To make changes, see ../vocab/autogen-hsk.rb

    // The hanzi values for these duplicate pinyin search keys were merged:
    <% duplicate_pinyin.uniq.each do |dp| %>//  <%= dp %>
    <% end %>
    pub const HANZI: &[&'static str] = &[
    <% merged_hanzi.each do |h| %>    &"<%= h %>",
    <% end %>];

    pub const PINYIN: &[&'static str] = &[
    <% merged_pinyin.each do |p| %>    &"<%= p %>",
    <% end %>];
    RUST
  rf.puts ERB.new(TEMPLATE).result(binding)
}
