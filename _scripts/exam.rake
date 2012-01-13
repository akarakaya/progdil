require 'erb'
require 'yaml'

task :exam do
Dir.foreach("_exams/") do |myfile|
if not ((myfile == ".") or (myfile == ".."))

file_path = YAML.load_file("_exams/"+myfile)
title = file_path["title"]
page_end = file_path["footer"]

question = file_path["q"]
#puts soru
r = 0
questions = []
for i in question
x = File.read("_includes/q/"+i)
questions[r] = x
r=r+1
end
puts questions
read_md = File.read("_templates/exam.md.erb")
oku = ERB.new(read_md)
y= oku.result(binding)
file = File.open("md_file.md","w")
file.write(y)
file.close
sh "markdown2pdf md_file.md"
sh "rm -f md_file.md"
end
end
end