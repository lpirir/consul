class Budget::Stats
  include Statisticable
  alias_method :budget, :resource

  def self.stats_methods
    %i[total_participants total_participants_support_phase total_participants_vote_phase
      total_budget_investments total_votes total_selected_investments
      total_unfeasible_investments total_male_participants total_female_participants
      total_supports total_unknown_gender_or_age age_groups male_percentage
      female_percentage headings total_participants_web total_participants_booths]
  end

  private

    def total_participants
      participants.distinct.count
    end

    def total_participants_support_phase
      voters.uniq.count
    end

    def total_participants_web
      (balloters - poll_ballot_voters).uniq.compact.count
    end

    def total_participants_booths
      poll_ballot_voters.uniq.count
    end

    def total_participants_vote_phase
      balloters.uniq.count
    end

    def total_budget_investments
      budget.investments.count
    end

    def total_votes
      budget.ballots.pluck(:ballot_lines_count).inject(0) { |sum, x| sum + x }
    end

    def total_selected_investments
      budget.investments.selected.count
    end

    def total_unfeasible_investments
      budget.investments.unfeasible.count
    end

    def total_male_participants
      participants.where(gender: "male").count
    end

    def total_female_participants
      participants.where(gender: "female").count
    end

    def total_supports
      supports(budget).count
    end

    def total_unknown_gender_or_age
      participants.where("gender IS NULL OR date_of_birth is NULL").uniq.count
    end

    def age_groups
      groups = Hash.new(0)
      ["16 - 19",
       "20 - 24",
       "25 - 29",
       "30 - 34",
       "35 - 39",
       "40 - 44",
       "45 - 49",
       "50 - 54",
       "55 - 59",
       "60 - 64",
       "65 - 69",
       "70 - 140"].each do |group|
        start, finish = group.split(" - ")
        group_name = (group == "70 - 140" ? "+ 70" : group)
        groups[group_name] = User.where(id: participants)
                                 .where("date_of_birth > ? AND date_of_birth < ?",
                                        finish.to_i.years.ago.beginning_of_year,
                                        start.to_i.years.ago.end_of_year).count
      end
      groups
    end

    def male_percentage
      total_male_participants / total_participants_with_gender.to_f * 100
    end

    def female_percentage
      total_female_participants / total_participants_with_gender.to_f * 100
    end

    def participants
      User.where(id: (authors + voters + balloters + poll_ballot_voters).uniq.compact)
    end

    def authors
      budget.investments.pluck(:author_id)
    end

    def voters
      supports(budget).pluck(:voter_id)
    end

    def balloters
      budget.ballots.where("ballot_lines_count > ?", 0).pluck(:user_id)
    end

    def poll_ballot_voters
      budget&.poll ? budget.poll.voters.pluck(:user_id) : []
    end

    def total_participants_with_gender
      participants.where.not(gender: nil).distinct.count
    end

    def balloters_by_heading(heading_id)
      stats_cache("balloters_by_heading_#{heading_id}") do
        budget.ballots.joins(:lines).where(budget_ballot_lines: {heading_id: heading_id}).pluck(:user_id)
      end
    end

    def voters_by_heading(heading)
      stats_cache("voters_by_heading_#{heading.id}") do
        supports(heading).pluck(:voter_id)
      end
    end

    def headings
      groups = Hash.new(0)
      budget.headings.order("id ASC").each do |heading|
        groups[heading.id] = Hash.new(0).merge(calculate_heading_totals(heading))
      end

      groups[:total] = Hash.new(0)
      groups[:total][:total_investments_count] = groups.collect {|_k, v| v[:total_investments_count]}.sum
      groups[:total][:total_participants_support_phase] = groups.collect {|_k, v| v[:total_participants_support_phase]}.sum
      groups[:total][:total_participants_vote_phase] = groups.collect {|_k, v| v[:total_participants_vote_phase]}.sum
      groups[:total][:total_participants_all_phase] = groups.collect {|_k, v| v[:total_participants_all_phase]}.sum

      budget.headings.each do |heading|
        groups[heading.id].merge!(calculate_heading_stats_with_totals(groups[heading.id], groups[:total], heading.population))
      end

      groups[:total][:percentage_participants_support_phase] = groups.collect {|_k, v| v[:percentage_participants_support_phase]}.sum
      groups[:total][:percentage_participants_vote_phase] = groups.collect {|_k, v| v[:percentage_participants_vote_phase]}.sum
      groups[:total][:percentage_participants_all_phase] = groups.collect {|_k, v| v[:percentage_participants_all_phase]}.sum

      groups
    end

    def calculate_heading_totals(heading)
      {
        total_investments_count: heading.investments.count,
        total_participants_support_phase: voters_by_heading(heading).uniq.count,
        total_participants_vote_phase: balloters_by_heading(heading.id).uniq.count,
        total_participants_all_phase: voters_and_balloters_by_heading(heading)
      }
    end

    def calculate_heading_stats_with_totals(heading_totals, groups_totals, population)
      {
        percentage_participants_support_phase: participants_percent(heading_totals, groups_totals, :total_participants_support_phase),
        percentage_district_population_support_phase: population_percent(population, heading_totals[:total_participants_support_phase]),
        percentage_participants_vote_phase: participants_percent(heading_totals, groups_totals, :total_participants_vote_phase),
        percentage_district_population_vote_phase: population_percent(population, heading_totals[:total_participants_vote_phase]),
        percentage_participants_all_phase: participants_percent(heading_totals, groups_totals, :total_participants_all_phase),
        percentage_district_population_all_phase: population_percent(population, heading_totals[:total_participants_all_phase])
      }
    end

    def voters_and_balloters_by_heading(heading)
      (voters_by_heading(heading) + balloters_by_heading(heading.id)).uniq.count
    end

    def participants_percent(heading_totals, groups_totals, phase)
      calculate_percentage(heading_totals[phase], groups_totals[phase])
    end

    def population_percent(population, participants)
      return "N/A" unless population.to_f.positive?
      calculate_percentage(participants, population)
    end

    def supports(supportable)
      ActsAsVotable::Vote.where(votable_type: "Budget::Investment", votable_id: supportable.investments.pluck(:id))
    end

    stats_cache(*stats_methods)
    stats_cache :total_participants_with_gender
    stats_cache :voters, :participants, :authors, :balloters, :poll_ballot_voters

    def stats_cache(key, &block)
      Rails.cache.fetch("budgets_stats/#{budget.id}/#{key}/v10", &block)
    end
end
