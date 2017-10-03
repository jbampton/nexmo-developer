class Diff
  def self.generate(mode:)
    document_paths = {
      documentation: {
        documents: Dir.glob("#{Rails.root}/_documentation/**/*.md"),
        origin: Pathname.new("#{Rails.root}/_documentation"),
        base_url_path: '',
      },
      api: {
        documents: Dir.glob("#{Rails.root}/_api/**/*.md"),
        origin: Pathname.new("#{Rails.root}/_api"),
        base_url_path: '/api',
      },
      tutorials: {
        documents: Dir.glob("#{Rails.root}/_tutorials/**/*.md"),
        origin: Pathname.new("#{Rails.root}/_tutorials"),
        base_url_path: '/tutorials',
      },
    }

    document_paths.each do |_, config|
      config[:documents].map do |document_path|
        document = File.read(document_path)
        body_html = MarkdownPipeline.new.call(document)

        document_path = Pathname.new(document_path)
        relative_path = "#{config[:base_url_path]}/#{document_path.relative_path_from(config[:origin])}".gsub('.md', '')

        path = "#{Rails.root}/tmp/diff/#{mode}/#{relative_path}.html"
        directory = File.dirname(path)
        FileUtils.mkdir_p(directory) unless File.directory?(directory)

        document = Nokogiri::HTML::DocumentFragment.parse(body_html)

        ['id', 'data-tabs-content', 'data-id', 'data-open'].each do |attribute|
          document.css("[#{attribute}]").each do |element|
            element[attribute] = nil
          end
        end

        document.css('.tabs a').each do |element|
          element['href'] = nil
        end

        File.open(path, 'w') do |file|
          file.write document.to_html
        end
      end
    end
  end

  def diff(mode)
    return @output if @output

    @output = []

    Dir.glob("#{Rails.root}/tmp/diff/base/**/*.html") do |base_document_path|
      compare_document_path = base_document_path.sub("#{Rails.root}/tmp/diff/base/", "#{Rails.root}/tmp/diff/compare/")

      base_document = File.read(base_document_path)
      compare_document = File.read(compare_document_path)
      path = base_document_path.sub("#{Rails.root}/tmp/diff/base", '').sub('.html', '')

      diff_response = Diffy::Diff.new(base_document, compare_document, context: 0).to_s(mode)

      unless diff_response.empty? || diff_response == "\n"
        @output << {
          path: path,
          diff: diff_response,
        }
      end
    end

    @output.reject!(&:empty?)
  end

  def report_cli
    if @output.any?
      puts "#{@output.size} changes detected".colorize(:light_red)
      @output.reject.each do |result|
        puts <<~HEREDOC
          #{result[:path]}

          #{result[:diff]}


        HEREDOC
      end

      exit 1
    else
      puts 'No changes detected'.colorize(:green)
    end
  end

  def report_pull_request
    if @output.any?
      time = Time.new.to_i
      branch = "code-example-update-#{time}"
      system "git checkout -b #{branch}"
      system 'git add .repos'
      system "git commit -m 'Automated: Updating code examples'"
      system 'git push origin'

      body =  "#{@output.size} changes detected\n".colorize(:light_red)
      @output.reject.each do |result|
        body << <<~HEREDOC
          ### `#{result[:path]}`

          ```diff
          #{result[:diff]}
          ```


        HEREDOC
      end

      RestClient.post 'https://requestb.in/qvd407qv', {
        'branch' => branch,
        'body' => body,
      }.to_json, {
        content_type: :json,
        accept: :json,
      }
    else
      puts 'No changes detected'.colorize(:green)
    end
  end
end
