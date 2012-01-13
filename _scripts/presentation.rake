
require 'pathname'   #pathname'i getirtir.
require 'pythonconfig' #pythonconfig'i getirtir.
require 'yaml'      #yaml'i getirtir.

CONFIG = Config.fetch('presentation', {}) #presentation dosyasına al getir.

PRESENTATION_DIR = CONFIG.fetch('directory', 'p') #directory dosyasına p'yi al getir.
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg') #conffile dosyasına _temlates/presentation.cfg yolundaki dosyayı al getir.
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html') #PRESENTATION_DIR ile index.html'yi birleştir ve INDEX_FILE'ye ata.
IMAGE_GEOMETRY = [ 733, 550 ]    #resim geometrilerini sabitleştirir.
DEPEND_KEYS = %w(source css js) #bağımlı anahtar
DEPEND_ALWAYS = %w(media) #bağımlı süreklilik
TASKS = {
    :index => 'sunumları indeksle',   # bundan sonraki yedi satır, her bir durumun görevini belirtilir.
    :build => 'sunumları oluştur',
    :clean => 'sunumları temizle',
    :view => 'sunumları görüntüle',
    :run => 'sunumları sun',
    :optim => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation = {}  #slaytlar
tag = {}    #taglar	

class File   #File sınıfı açar.
  @@absolute_path_here = Pathname.new(Pathname.pwd) #dosya yolunu alır. 
  def self.to_herepath(path) #	
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?       #dosya yolu aynı mı diye kontrol eder aynıysa dosyaları listeler.
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string)  #dosya yolunu oluşturan stringi yorumlar.
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked' #açılmış olan dosya için raked yorumunu yapar ve kaydeder.
  image.save(file)
end

def png_optim(file, threshold=40000)  #png dosyalarını en uygun hale getirir.
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out) #dosyanın varlığını kontrol eder.
    $?.success? ? File.rename(out, file) : File.delete(out) #eğer varsa file adıyla yeniden adlandırır ve out dosyasını siler.
  end
  png_comment(file, 'raked')  # raked olarak yorumlar.
end

def jpg_optim(file) #jpg dosyalarını en uygun hale getirir.
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}" # raked olarak yorumlar.
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"] #jpeg ve png dosyalarını listeler.

  [pngs, jpgs].each do |a|   #her bir jpeg ve png dosyasını sabitlenmiş şekle getirir.
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i } #her bir jpeg ve png dosyalarının boyutlarını belirler.
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) } #her bir jpeg ve png dosyası belirlenen boyutlarla en uygun hale getirilir.
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir) 
  chdir dir do
    name = File.basename(dir)  #slayt dosyalarının uzantılarına karar verilir.
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide     #landslide bölümü tanımlanmış mı diye kontrol eder.
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış" #tanımlanmamışsa ekrana hata basar.
      exit 1
    end

    if landslide['destination'] #destination ayarı kullanılıp kullanılmadığını kontrol eder.
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin" #kullanılmışsa ekrana hata basar.
      exit 1
    end

    if File.exists?('index.md') #index.md'nin varlığını kontrol eder.
      base = 'index'
      ispublic = true #dışarı açık olmalı
    elsif File.exists?('presentation.md') #presentation.md'nin varlığını kontrol eder.
      base = 'presentation'
      ispublic = false #dışarı kapalı olmalı
    else  #bunların dışındaki durumlarda ise
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı" #ekrana hata basar.
      exit 1
    end

    basename = base + '.html' #.md dosyasını .html yap
    thumbnail = File.to_herepath(base + '.png') #png uzantısıyla başlangıcı oluştur.
    target = File.to_herepath(basename) #hedef oluştur.

    deps = [] 
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target) #targeti sil.
    deps.delete(thumbnail) #thumbnaili sil.

    tags = []

   presentation[dir] = {
      :basename => basename, # üreteceğimiz sunum dosyasının baz adı
      :conffile => conffile, # landslide konfigürasyonu (mutlak dosya yolu)
      :deps => deps, # sunum bağımlılıkları
      :directory => dir, # sunum dizini (tepe dizine göreli)
      :name => name, # sunum ismi
      :public => ispublic, # sunum dışarı açık mı
      :tags => tags, # sunum etiketleri
      :target => target, # üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, # sunum için küçük resim
    }
  end
end

presentation.each do |k, v| #sunum dosyalarındaki eksik taglar tamamlanır. 
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten] #görev haritası

presentation.each do |presentation, data|
  ns = namespace presentation do  #isim uzayı oluştur.
    file data[:target] => data[:deps] do |t| #targetin içeriğini aktar, sunumu oluştur.
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do  #resmi hedefe gönderir.
      next unless data[:public] #bir sonrakinin public olup olmadığını kontrol eder.
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " + # küçük resimin boyutlarını düzenleyerek en uygun hale getirir.
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end

    task :optim do  # en uygun hale getirme işlemi yapılıyor.
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail] #görevler arasındaki index'i küçük resime uygular. 

    task :build => [:optim, data[:target], :index] #görevler arasındaki build'i uygular.

    task :view do
      if File.exists?(data[:target]) #target'deki belirtilen dosyanın olup olmadığını kontrol eder.
        sh "touch #{data[:directory]}; #{browse_command data[:target]}" #eğer dosya varsa istenileni uygular.
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin" #yoksa ekrana hata basar.
      end
    end

    task :run => [:build, :view] #run görevi için build görevi ve view görevi gerekir.

    task :clean do #clean görevinin işlevi target ve thumbnail'i temizler.
      rm_f data[:target] 
      rm_f data[:thumbnail]
    end

    task :default => :build #varsayılan görev build'dir.
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym) #yeni görevler eklenir.
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do     # isim uzayında eklenen yeni görevlerle isim ve bilgileri oluşturur.
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(INDEX_FILE) || {} #INDEX_FILE'yi yükler.
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort #dosyaları seçer.
    unless index and presentations == index['presentations'] # eğer eşit ise INDEX_FILE'i açar ve içerisine index.to_yaml'i ve --- yazar.
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menüsü"
  task :menu do #menu görevi işlemlerin ismini, rengini, oluşturulma zamanını vs düzenler.
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1" #varsayılan değer 1'dir.
      menu.prompt = color( 
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke #rake'yi çalıştırır.
  end
  task :m => :menu # oluşturulan m görevi, menu görevi aracılığıyla çalıştırılır.
end

desc "sunum menüsü"
task :p => ["p:menu"] #menuyu p ile çalıştır.
task :presentation => :p #presentation görevini oluştur.