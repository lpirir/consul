require "rails_helper"

feature "Email campaigns" do

  background do
    @campaign1 = create(:campaign)
    @campaign2 = create(:campaign)

    admin = create(:administrator)
    login_as(admin.user)
  end

  scenario "Track email templates" do
    3.times { visit root_url(track_id: @campaign1.track_id) }
    5.times { visit root_url(track_id: @campaign2.track_id) }

    visit admin_stats_path
    click_link @campaign1.name

    expect(page).to have_content "#{@campaign1.name} (3)"

    click_link "Go back"
    click_link @campaign2.name

    expect(page).to have_content "#{@campaign2.name} (5)"
  end

  scenario "Do not track erroneous track_ids" do
    visit root_url(track_id: @campaign1.track_id)
    visit root_url(track_id: "999")

    visit admin_stats_path
    click_link @campaign1.name

    expect(page).to have_content "#{@campaign1.name} (1)"

    click_link "Go back"

    expect(page).not_to have_content @campaign2.name.to_s
  end

end
