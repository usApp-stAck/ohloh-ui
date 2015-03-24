class ProjectsController < ApplicationController
  helper AnalysesHelper
  helper FactoidsHelper
  helper RatingsHelper

  before_action :session_required, only: [:create, :new, :update]
  before_action :api_key_lock, only: [:index]
  before_action :find_account
  before_action :find_projects, only: [:index]
  before_action :find_project, only: [:show, :edit, :update, :estimated_cost, :users]
  before_action :redirect_new_landing_page, only: :index
  before_action :project_context, only: [:show, :users, :estimated_cost]

  def index
    respond_to do |format|
      format.html { render template: @account ? 'projects/index_managed' : 'projects/index' }
      format.xml
      format.atom
    end
  end

  def show
    @analysis = @project.best_analysis
    @rating = logged_in? ? @project.ratings.where(account_id: current_user.id).first : nil
    @score = @rating ? @rating.score : 0
  end

  def users
    @accounts = @project.users(params[:query], params[:sort])
                .paginate(page: params[:page], per_page: 10,
                          total_entries: @project.users.count('DISTINCT(accounts.id)'))
  end

  def update
    return render_unauthorized unless @project.edit_authorized?
    if @project.update_attributes(project_params)
      flash[:notice] = t '.success'
      redirect_to project_path(@project)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # TODO: this really belongs in app_controller, but that file is too big currently
  def api_key_lock
    return unless request_format == 'xml'
    api_key = ApiKey.in_good_standing.where(key: params[:api_key]).first
    render_unauthorized unless api_key && api_key.may_i_have_another?
  end

  def find_account
    @account = Account.in_good_standing.from_param(params[:account_id]).take
  end

  def find_projects
    projects = @account ? @account.projects.not_deleted : Project.not_deleted
    sort_by = parse_sort_term(projects)
    @projects = projects.tsearch(params[:query], sort_by).page(params[:page]).per_page(10)
  end

  def parse_sort_term(projects)
    projects.respond_to?("by_#{params[:sort]}") ? "by_#{params[:sort]}" : nil
  end

  def find_project
    @project = Project.not_deleted.from_param(params[:id]).take
    fail ParamRecordNotFound unless @project
    @project.editor_account = current_user
  end

  def project_params
    params.require(:project).permit([:name, :description, :url_name])
  end

  def redirect_new_landing_page
    return unless @account.nil?
    redirect_to explore_projects_path if request.query_parameters.except('action').empty? && request_format == 'html'
  end
end
