class UsersController < ApplicationController
  respond_to :html, :json
  layout 'blank'
  before_filter :authenticate_user!, except: [:authenticate_for_token]

  def show
     @user = User.find(params[:id])
  end

  def edit 
     @user = User.find(params[:id])
  end

  def update
     @user = User.find(params[:id])
     @user.attributes = params[:user]
     @user.roles.each do |role|
       @join = Assignment.where(role_id: role.id, user_id: @user.id).first
       if @join == nil
        @join = Assignment.new :assigner => current_user, :role => role, :user => @user 
        @join.save
       elsif @join.assigner_id == nil
         @join.assigner_id = current_user.id
         @join.save
       end
     end
     if @user.save
       redirect_to user_path(@user)
     else
       redirect_to edit_user_path(@user)
     end
  end

  def index
    @users = User.page params[:page]
    authorize! :read, @users
    respond_to do |format|
      format.html { @users = User.page params[:page] }
      format.json { render :json => User.all }
    end
  end


  def find
    @user = User.where(player_name: params[:player_name]).first
    respond_to do |format|
      if @user.present?
        format.any { redirect_to user_path(@user) }
      else
        flash[:error] = 'Player name not found'
        format.any { redirect_to :back }
      end
    end
  end
  

  def authenticate_for_token
    @user = User.with_login(params[:email]).first
    ret = {}
    if @user != nil and @user.valid_password? params[:password]
      @auth_token = @user.authentication_token
      ret = {:session_id => 'remove me', :auth_token => @auth_token}
      respond_to do |format|
        format.json {render :json => ret, :status => :created }
        format.xml  {render :xml => ret, :status => :created }
      end
    else
      ret = {:error => "Invalid email or password"}
      respond_to do |format|
        format.json {render :json => ret, :status => :unauthorized }
        format.xml  {render :xml => ret, :status => :unauthorized }
      end
    end
  end

  def new_sequence
    @user_sequence = UserSequence.new
  end

  def create_sequence
    @user_sequence = UserSequence.new params[:user_sequence]

    if @user_sequence.valid?

      @user_sequence.create_users!

      respond_to do |format|
        format.html { redirect_to users_path }
        format.json { render :json => @user_sequence, :status => :created }
      end
    else
      respond_to do |format|
        format.html { render 'new_sequence' }
        format.json { render :json => @user_sequence }
      end
    end
  end

  def get_data
    if params[:level] != nil
      @data = AdaData.where(user_id: params[:user_id], gameName: params[:gameName], schema: params[:schema], level: params[:level], key: params[:key])
    else
      @data = AdaData.where(user_id: params[:user_id], gameName: params[:gameName], schema: params[:schema], key: params[:key])
    end
    respond_to do |format|
      format.json { render :json => @data }
    end
  end

  def data_by_game
    @user = User.find(params[:id])
    @game = Game.find_by_name(params[:gameName])
    authorize! :read, @game 
    @data = AdaData.where(user_id: params[:id], gameName: params[:gameName]) 
    respond_to do |format| 
      format.csv {send_data export_csv(@data, @user.player_name), filename: @user.player_name+'_'+@game.name+'.csv'} 
    end
  end

  def reset_password_form
    @user = User.new params[:user]
  end

  def reset_password
    @user = User.with_login(params[:user][:player_name]).first

    if @user.nil?
      respond_to do |format|
        format.html { flash[:alert] = "Invalid Player"; redirect_to reset_password_form_users_url }
      end
    else
      if can_change_password_for? @user
        @user.password = params[:user][:password]

        if @user.save
          respond_to do |format|
            format.html { flash[:notice] = "Password Changed!"; redirect_to reset_password_form_users_url }
          end
        else
          respond_to do |format|
            format.html { render :reset_password_form }
          end
        end
      else
        respond_to do |format|
          format.html { flash[:alert] = "Not Authorized"; redirect_to reset_password_form_users_url }
        end
      end
    end
  end


  protected

  def application
    @application ||= Client.where(app_token: params[:client_id]).first
  end

  def export_csv(data, name)
    CSV.generate do |csv|
      keys = Hash.new
      data.each do |log_entry|
        csv << JSON.parse(log_entry.as_document.to_json).values
      end 
    end 
  end

  def can_change_password_for?(user)
    json_body = {student_user_id: user.id}
    auth_response = HTTParty.get("#{Rails.configuration.password_change_authorization_server}/accounts/#{current_user.id}/can_change_password_for.json", body: json_body)
    return (auth_response.code == 200)
  end
end
