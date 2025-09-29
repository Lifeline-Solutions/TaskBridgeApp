module ProfilesHelper
  def format_full_duration_human(total_seconds)
    return 'less than a minute' if total_seconds < 60

    units = [
      [:year, 31_536_000],
      [:month, 2_592_000],
      [:week, 604_800],
      [:day, 86_400],
      [:hour, 3_600],
      [:minute, 60]
    ]

    remaining = total_seconds.to_i
    parts = []

    units.each do |name, secs|
      count = remaining / secs
      if count > 0
        parts << "#{count} #{name}#{'s' if count > 1}"
        remaining -= count * secs
      end
    end

    parts.join(', ')
  end
end
