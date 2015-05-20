class TagsController < ApplicationController
  helper ProjectsHelper
  helper RatingsHelper

  before_action :find_models, only: [:index]
  before_action :show_permissions_alert, only: :select
  before_action :set_session_projects, only: :index

  private

  def find_models
    params[:names] ? find_projects_by_names : find_tags_by_popularity
  end

  def find_projects_by_names
    @projects = Project.tagged_with(params[:names])
                .includes([[best_analysis: :main_language], :logo, :organization, :licenses])
                .order(user_count: :desc)
                .page(params[:page]).per_page(10)
    @projects.each { |proj| proj.editor_account = current_user }
    find_related_tags
  end

  def find_related_tags
    tags = Tag.where(name: params[:names]).pluck("name||' (' || taggings_count || ')', name")
    related_tags = Tag.related_tags(params[:names])
                   .order(count: :desc)
                   .pluck("name|| ' (' || count(*) || ')', name")
    @related_tags = tags + related_tags
  end

  def find_tags_by_popularity
    @tags = Tag.popular.paginate(page: params[:page], per_page: 48)
    render template: 'tags/cloud'
  end

  def projects_with_all_tags(tag_ids)
    ins = tag_ids.collect do |tag_id|
      "projects.id IN (SELECT taggable_id FROM taggings WHERE tag_id=#{tag_id} AND taggable_type='Project')"
    end
    Project.not_deleted.where(ins.join(' AND ')).order(user_count: :desc).paginate(page: params[:page], per_page: 10)
  end
end
