require "pronto/ignored_columns/version"
require "pronto"
require "pry"

module Pronto
  class IgnoreColumns < Runner
    def run
      deleted_columns = @patches
        .map { |patch| DeleteColumnsScanner.new(patch).scan }
        .flatten
    end
  end

  class DeleteColumnsScanner
    attr_reader :patch

    def initialize(patch)
      @patch = patch
      @deleted_columns = []
      @modified_model = []
      @table_name = table_name
    end

    def messages
      scan
      @deleted_columns.each do |deleted_column|
        patch.added_lines.each do |line|
          next unless modified_model?(deleted_column[:table_name])

          line.patch.delta.new_file[:path]
        end
      end
    end

    def modified_model?(table_name)
      base_path = patch.repo.path + "app/models"

      File.exist?(base_path + table_name.singularize + ".rb")
    end

    def new_message(deleted_column, line)
      path = line.patch.delta.new_file[:path]
      label = :warning
      message = create_message(deleted_column)

      Message.new(path, line, lebel, message, nil, runner.class )
    end

    def table_name
      patch.new_file_full_path.basename(".schema").to_s
    end

    def scan
      scan_for_deleted_columns
      scan_for_modified_models
    end

    def scan_for_deleted_columns
      patch
        .deleted_lines
        .select { |patch| patch.delta.new_file[:path].end_with?("schema") }
        .each do |dl|
          next if dl.line.content.start_with?("add_foreign_key")

          @deleted_columns << {
            table_name: @table_name,
            column_name: Parser.new.parse(dl.line.content),
            line: dl
          }
        end
    end

    def scan_for_modified_models
      patch
        .added_lines
        .select { |l| l.delta.new_file[:path].match? /app\/models/ }
        .each do |al|
          @modified_model << {
            model_name: guess_model_name(al),
            line: al
          }
        end
    end

    def guess_model_name(line)
      line.delta.new_file[:path].basename(".rb")
    end
  end
end
