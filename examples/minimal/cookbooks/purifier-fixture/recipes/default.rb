answer = 42
file ENV.fetch('PURIFIER_PROOF_OUTPUT') do
  content "answer=0\n"
end
replace_or_add 'purifier-answer' do
  path ENV.fetch('PURIFIER_PROOF_OUTPUT')
  pattern '^answer='
  line "answer=#{answer}"
end
