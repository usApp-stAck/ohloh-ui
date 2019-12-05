# frozen_string_literal: true

class Analysis::CommitVolume < Analysis::QueryBase
  arel_tables :name, :analysis_sloc_set, :commit, :analysis_alias

  def initialize(analysis, interval)
    @analysis = analysis
    @interval = interval
  end

  def collection
    execute.map { |row| [row.committer_name, row.count] }
  end

  private

  def execute
    # FDW: joins FDW tables(code_sets, commits, analysis_sloc_sets & analysis_aliases) to get analysis. #API
    Analysis.select([name.as('committer_name'), Arel.star.count.as('count')])
            .joins(analysis_sloc_sets: { sloc_set: { code_set: :commits } }, analysis_aliases: :preferred_name)
            .where(conditions)
            .where(id: @analysis.id)
            .where(["commits.time >= analyses.max_month + INTERVAL '1 month' - INTERVAL ? ", @interval])
            .group(name)
            .order('count DESC, LOWER(names.name)')
  end

  def name
    names[:name]
  end

  def conditions
    commits[:position].lteq(analysis_sloc_sets[:as_of]).and commits[:name_id].eq(analysis_aliases[:commit_name_id])
  end
end
