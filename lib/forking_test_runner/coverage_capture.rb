module ForkingTestRunner
  module CoverageCapture
    # override Coverage.result to add pre-fork captured coverage
    def result
      return super unless captured = CoverageCapture.coverage
      CoverageCapture.merge_coverage(super, captured)
    end

    # deprecated, single_cov checks for this, so leave it here
    def capture_coverage!
    end

    class << self
      attr_accessor :coverage

      def activate!
        require 'coverage'
        (class << Coverage; self; end).prepend self
      end

      def capture!
        self.coverage = Coverage.peek_result.dup
      end

      def merge_coverage(a, b)
        if defined?(SingleCov)
          covered_files = SingleCov::COVERAGES.map do |file, uncovered|
            "#{SingleCov.send(:root)}/#{file}"
          end

          merged = covered_files.each_with_object({}) do |file, obj|
            if coverage = b[file]
              orig = a[file]
              obj[file] = if coverage.is_a?(Array)
                merge_lines_coverage(orig, coverage)
              else
                {
                  lines: merge_lines_coverage(orig.fetch(:lines), coverage.fetch(:lines)),
                  branches: merge_branches_coverage(orig.fetch(:branches), coverage.fetch(:branches))
                }
              end
            end
          end
        else
          merged = a.dup

          b.each do |file, coverage|
            orig = merged[file]
            merged[file] = if orig
              if coverage.is_a?(Array)
                merge_lines_coverage(orig, coverage)
              else
                {
                  lines: merge_lines_coverage(orig.fetch(:lines), coverage.fetch(:lines)),
                  branches: merge_branches_coverage(orig.fetch(:branches), coverage.fetch(:branches))
                }
              end
            else
              coverage
            end
          end
        end

        merged
      end

      private

      # assuming b has same or more keys since it comes from a fork
      # [nil,1,0] + [nil,nil,2] -> [nil,1,2]
      def merge_lines_coverage(a, b)
        b.each_with_index.map do |b_count, i|
          a_count = a[i]
          (a_count.nil? && b_count.nil?) ? nil : a_count.to_i + b_count.to_i
        end
      end

      # assuming b has same or more keys since it comes from a fork
      # {foo: {bar: 0, baz: 1}} + {foo: {bar: 1, baz: 0}} -> {foo: {bar: 1, baz: 1}}
      def merge_branches_coverage(a, b)
        b.each_with_object({}) do |(branch, v), all|
          vb = v.dup
          if part = a[branch]
            part.each do |nested, a_count|
              vb[nested] = a_count + vb[nested].to_i
            end
          end
          all[branch] = vb
        end
      end
    end
  end
end
