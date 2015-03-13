#contains all functions related to management of the signup sheet for an assignment
#functions to add new topics to an assignment, edit properties of a particular topic, delete a topic, etc
#are included here

#A point to be taken into consideration is that :id (except when explicitly stated) here means topic id and not assignment id
#(this is referenced as :assignment id in the params has)
#The way it works is that assignments have their own id's, so do topics. A topic has a foreign key dependecy on the assignment_id
#Hence each topic has a field called assignment_id which points which can be used to identify the assignment that this topic belongs
#to

class SignupSheetController < ApplicationController
  require 'rgl/adjacency'
  require 'rgl/dot'
  require 'rgl/topsort'

  def action_allowed?
    puts "2222222 call action_allowed?"
    case params[:action]
    when 'signup_topics', 'sign_up', 'delete_signup', 'index', 'show_team'
      current_role_name.eql? 'Student'
    else
      ['Instructor',
       'Teaching Assistant',
       'Administrator',
       'Super-Administrator'].include? current_role_name
    end
  end

  #Includes functions for team management. Refer /app/helpers/ManageTeamHelper
  include ManageTeamHelper
  #Includes functions for Dead line management. Refer /app/helpers/DeadLineHelper
  include DeadlineHelper

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify method: 'post', :only => [:destroy, :create, :update],
    :redirect_to => {:action => :index}

  # Prepares the form for adding a new topic. Used in conjuntion with create
  def new
    puts "2222222 call new"
    @id = params[:id]
    @sign_up_topic = SignUpTopic.new
    @sign_up_topic.assignment = Assignment.find(params[:id])
    @topic = @sign_up_topic
  end

  def update_topic_info(topic)
    topic.topic_identifier = params[:topic][:topic_identifier]
    #While saving the max choosers you should be careful; if there are users who have signed up for this particular
    #topic and are on waitlist, then they have to be converted to confirmed topic based on the availability. But if
    #there are choosers already and if there is an attempt to decrease the max choosers, as of now I am not allowing
    #it.
    if SignedUpUser.find_with_topic_id(topic.id).nil? || topic.max_choosers == params[:topic][:max_choosers]
      topic.max_choosers = params[:topic][:max_choosers]
    else
      if topic.max_choosers.to_i < params[:topic][:max_choosers].to_i
        topic.update_waitlisted_users(params[:topic][:max_choosers])
        topic.max_choosers = params[:topic][:max_choosers]
      else
        flash[:error] = 'Value of maximum choosers can only be increased! No change has been made to max choosers.'
      end
    end
  end

  def check_after_create
    if @assignment.is_microtask?
      @sign_up_topic.micropayment = params[:topic][:micropayment]
    end
    if @assignment.staggered_deadline?
      topic_set = Array.new
      topic = @sign_up_topic.id
    end
  end

  #This method is used to create signup topics
  #In this code params[:id] is the assignment id and not topic id. The intuition is
  #that assignment id will virtually be the signup sheet id as well as we have assumed
  #that every assignment will have only one signup sheet
  def create
    puts "2222222 call create"
    topic = SignUpTopic.find_with_name_and_assignment_id(params[:topic][:topic_name], params[:id]).first
    #if the topic already exists then update
    if topic
      update_topic_info(topic)
      topic.category = params[:topic][:category]
      topic.save
      redirect_to_sign_up(params[:id])
    else
      set_values_for_new_topic
      check_after_create
      if @sign_up_topic.save
        #NotificationLimit.create(:topic_id => @sign_up_topic.id)
        undo_link("Topic: \"#{@sign_up_topic.topic_name}\" has been created successfully. ")
        #changing the redirection url to topics tab in edit assignment view.
        redirect_to edit_assignment_path(@sign_up_topic.assignment_id) + "#tabs-5"
      else
        render action: 'new', id: params[:id]
      end
    end
  end


  #This method is used to delete signup topics
  #Renaming delete method to destroy for rails 4 compatible
  def destroy
    puts "2222222 call destroy"
    @topic = SignUpTopic.find(params[:id])
    if @topic
      @topic.destroy
      undo_link("Topic: \"#{@topic.topic_name}\" has been deleted successfully. ")
    else
      flash[:error] = "Topic could not be deleted"
    end
    #if this assignment has staggered deadlines then destroy the dependencies as well
    destroy_dependencies
    #changing the redirection url to topics tab in edit assignment view.
    redirect_to edit_assignment_path(params[:assignment_id]) + "#tabs-5"
  end

  def destroy_dependencies
    if Assignment.find(params[:assignment_id])['staggered_deadline']
      dependencies = TopicDependency.find_with_topic_id(params[:id])
      unless dependencies.nil?
        dependencies.each { |dependency| dependency.destroy }
      end
    end
  end

  #prepares the page. shows the form which can be used to enter new values for the different properties of an assignment
  def edit
    puts "2222222 call edit"
    @topic = SignUpTopic.find(params[:id])
  end


    #updates the database tables to reflect the new values for the assignment. Used in conjuntion with edit
  def update
    puts "2222222 call update"
    @topic = SignUpTopic.find(params[:id])

    if @topic
      update_topic_info(@topic)
      #update tables
      @topic.category = params[:topic][:category]
      @topic.topic_name = params[:topic][:topic_name]
      @topic.micropayment = params[:topic][:micropayment]
      @topic.save
      undo_link("Topic: \"#{@topic.topic_name}\" has been updated successfully. ")
    else
      flash[:error] = "Topic could not be updated"
    end
    #changing the redirection url to topics tab in edit assignment view.
    redirect_to edit_assignment_path(params[:assignment_id]) + "#tabs-5"
  end

  #This displays a page that lists all the available topics for an assignment.
      #Contains links that let an admin or Instructor edit, delete, view enrolled/waitlisted members for each topic
      #Also contains links to delete topics and modify the deadlines for individual topics. Staggered means that different topics
      #can have different deadlines.
      def topic_and_duedate
        puts "2222222 call add_signup_topic"
        list_signup_topics
        set_duedate_info
      end

      def set_duedate_info
        @review_rounds = Assignment.find(params[:id]).get_review_rounds
        @topics = SignUpTopic.find_with_assignment_id( params[:id])
        #Use this until you figure out how to initialize this array
        @duedates = SignUpTopic.find_topic_id_with_assignment_id(params[:id].to_s)
        unless @topics.nil?
          i=0
          @topics.each { |topic|
            @duedates[i]['t_id'] = topic.id
            @duedates[i]['topic_identifier'] = topic.topic_identifier
            @duedates[i]['topic_name'] = topic.topic_name
            for j in 1..@review_rounds
              duedate_subm = TopicDeadline.find_with_tid_and_dtype(topic.id, DeadlineType.find_with_name('submission').id).first
              duedate_rev = TopicDeadline.find_with_tid_and_dtype(topic.id, DeadlineType.find_with_name('review').id).first
              if !duedate_subm.nil? && !duedate_rev.nil?
                @duedates[i]['submission_'+ j.to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
                @duedates[i]['review_'+ j.to_s] = DateTime.parse(duedate_rev['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
              else
                #the topic is new. so copy deadlines from assignment
                set_of_due_dates = DueDate.find_with_aid(params[:id])
                set_of_due_dates.each { |due_date|
                  create_topic_deadline(due_date, 0, topic.id)
                }
                @duedates[i]['submission_'+ j.to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
                @duedates[i]['review_'+ j.to_s] = DateTime.parse(duedate_rev['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
              end
            end
            duedate_subm = TopicDeadline.find_with_tid_and_dtype(topic.id,  DeadlineType.find_with_name('metareview').id).first
            @duedates[i]['submission_'+ (@review_rounds+1).to_s] = !(duedate_subm.nil?)?(DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")):nil
            i = i + 1
          }
        end
      end
      def list_signup_topics_staggered
        topic_and_duedate
      end
      #similar to the above function except that all the topics and review/submission rounds have the similar deadlines
      def list_signup_topics
        puts "2222222 call add_signup_topics"
        load_signup_topics(params[:id])
      end

      #Seems like this function is similar to the above function> we are not quite sure what publishing rights mean. Seems like
      #the values for the last column in http://expertiza.ncsu.edu/student_task/list are sourced from here
      def view_publishing_rights
        puts "2222222 call view_publishing_rights"
        load_signup_topics(params[:id])
      end

      #retrieves all the data associated with the given assignment. Includes all topics,
      #participants(people who are doing this assignment) and signed up users (people who have chosen a topic (confirmed or waitlisted)
      def load_signup_topics(assignment_id)
        puts "aaaaaaaaaaaaaaaa"
        puts "2222222 call load_add_signup_topics"
        @id = assignment_id
        @sign_up_topics = SignUpTopic.find_with_assignment_id(assignment_id)
        filled_and_waitlisted_topics(@id)
        @assignment = Assignment.find(assignment_id)
        #ACS Removed the if condition (and corresponding else) which differentiate assignments as team and individual assignments
        # to treat all assignments as team assignments
        @participants = SignedUpUser.find_team_participants(assignment_id)
      end

      def filled_and_waitlisted_topics(assignment_id)
        @slots_filled = SignUpTopic.find_slots_filled(assignment_id)
        @slots_waitlisted = SignUpTopic.find_slots_waitlisted(assignment_id)
      end

      def set_values_for_new_topic
        puts "2222222 call set_values_for_new_topic"
        @sign_up_topic = SignUpTopic.new
        @sign_up_topic.topic_identifier = params[:topic][:topic_identifier]
        @sign_up_topic.topic_name = params[:topic][:topic_name]
        @sign_up_topic.max_choosers = params[:topic][:max_choosers]
        @sign_up_topic.category = params[:topic][:category]
        @sign_up_topic.assignment_id = params[:id]
        @assignment = Assignment.find(params[:id])
      end

      #simple function that redirects ti the /add_signup_topics or the /add_signup_topics_staggered page depending on assignment type
      #staggered means that different topics can have different deadlines.
      def redirect_to_sign_up(assignment_id)
        puts "2222222 call redirect_to_sign_up"
        assignment = Assignment.find(assignment_id)
        (assignment.staggered_deadline)?(redirect_to action: 'topic_and_duedate', id: assignment_id):(redirect_to action: 'signup_topics', id: assignment_id)
      end

      def index
        puts "2222222 call list"
        @assignment_id = params[:id]
        @sign_up_topics =SignUpTopic.find_with_assignment_id( params[:id]).all
        filled_and_waitlisted_topics(@assignment_id)
        @show_actions = true
        @priority = 0
        assignment=Assignment.find(params[:id])
        #end
        if assignment.due_dates.find_by_deadline_type_id(1)!= nil
          unless !(assignment.staggered_deadline? and assignment.due_dates.find_by_deadline_type_id(1).due_at < Time.now )
            @show_actions = false
          end
          #Find whether the user has signed up for any topics; if so the user won't be able to
          #sign up again unless the former was a waitlisted topic
          #if team assignment, then team id needs to be passed as parameter else the user's id
          users_team = SignedUpUser.find_team_users(params[:id],(session[:user].id))
          if users_team.size == 0
            @selected_topics = nil
          else
            #TODO: fix this; cant use 0
            @selected_topics = SignupSheetController.other_confirmed_topic_for_user(params[:id], users_team[0].t_id)
          end
          SignUpTopic.remove_team(users_team, @assignment_id)
          end
        end


        #this function is used to delete a previous signup
        def delete_signup
          @user_id = session[:user].id
          SignUpTopic.reassign_topic(@user_id,params[:assignment_id], params[:id])
          redirect_to action: 'index', id: params[:assignment_id]
        end

        def sign_up
          puts "2222222 call sign_up"
          #find the assignment to which user is signing up
          @assignment = Assignment.find(params[:assignment_id])
          @user_id = session[:user].id
          #check whether team assignment. This is to decide whether a team_id or user_id should be the creator_id
          #Always use team_id ACS
          #s = Signupsheet.new
          #check whether the user already has a team for this assignment
          signup_team(@assignment.id, @user_id, params[:id])
          redirect_to action: 'index', id: params[:assignment_id]
        end

        def signup_team(assignment_id, user_id, topic_id)
          puts "2222222 call signup_team"
          users_team = SignedUpUser.find_team_users(assignment_id, user_id)
          if users_team.size == 0
            #if team is not yet created, create new team.
            team = AssignmentTeam.create_team_and_node(assignment_id)
            user = User.find(user_id)
            teamuser = create_team_users(user, team.id)
            confirmationStatus = confirm_topic(team.id, topic_id, assignment_id)
          else
            confirmationStatus = confirm_topic(users_team[0].t_id, topic_id, assignment_id)
          end
        end

        def confirm_topic(creator_id, topic_id, assignment_id)
          puts "2222222 call confirmTopic"
          #check whether user has signed up already
          user_signup = SignupSheetController.other_confirmed_topic_for_user(assignment_id, creator_id)

          sign_up = SignedUpUser.new
          sign_up.topic_id = params[:id]
          sign_up.creator_id = creator_id
          result = false
         check_slot_and_db_transaction(creator_id,topic_id,assignment_id,sign_up,user_signup,result)
        end

        def check_slot_and_db_transaction(creator_id,topic_id,assignment_id,sign_up,user_signup,result)
          if user_signup.empty?
            # Using a DB transaction to ensure atomic inserts

            ActiveRecord::Base.transaction do
              #check whether slots exist (params[:id] = topic_id) or has the user selected another topic
              if slotAvailable?(topic_id)
                sign_up.is_waitlisted = false

                #Update topic_id in participant table with the topic_id
                participant = Participant.find_participant_byassign( session[:user].id,assignment_id).first

                participant.update_topic_id(topic_id)
              else
                sign_up.is_waitlisted = true
              end
              if sign_up.save
                result = true
              end
            end
          else
            #If all the topics choosen by the user are waitlisted,
            for user_signup_topic in user_signup
              if user_signup_topic.is_waitlisted == false
                flash[:error] = "You have already signed up for a topic."
                return false
              end
            end

            # Using a DB transaction to ensure atomic inserts
            ActiveRecord::Base.transaction do
              #check whether user is clicking on a topic which is not going to place him in the waitlist
              if !slotAvailable?(topic_id)
                sign_up.is_waitlisted = true
                if sign_up.save
                  result = true
                end
              else
                #if slot exist, then confirm the topic for the user and delete all the waitlist for this user
                Waitlist.cancel_all_waitlists(creator_id, assignment_id)
                sign_up.is_waitlisted = false
                sign_up.save
                participant = Participant.find_participant_byassign(session[:user].id,assignment_id).first
                participant.update_topic_id(topic_id)
                result = true
              end
            end
          end
          result
        end
        # When using this method when creating fields, update race conditions by using db transactions
        def slotAvailable?(topic_id)
          puts "2222222 call slotAvailable?"
          SignUpTopic.slotAvailable?(topic_id)
        end

        def self.other_confirmed_topic_for_user(assignment_id, creator_id)
          puts "2222222 call other_confirmed_topic_for_user"
          user_signup = SignedUpUser.find_user_signup_topics(assignment_id, creator_id)
          user_signup
        end

        def set_priority
          puts "2222222 call set_priority"
          @user_id = session[:user].id
          users_team = SignedUpUser.find_team_users(params[:assignment_id].to_s, @user_id)
          check = SignedUpUser.find_checks(params[:assignment_id].to_s,users_team[0].t_id,params[:priority].to_s)
          if check.empty?
            signUp = SignedUpUser.find_signup_priority(params[:id],users_team[0].t_id).first
            #signUp.preference_priority_number = params[:priority].to_s
            if params[:priority].to_s.to_f > 0
              signUp.update_attribute('preference_priority_number' , params[:priority].to_s)
            else
              flash[:error] = "Invalid priority"
            end
          end
          redirect_to action: 'index', id: params[:assignment_id]
        end

        #this function is used to prevent injection attacks.  A topic *dependent* on another topic cannot be
        # attempted until the other topic has been completed..
        def save_topic_dependencies
          puts "2222222 call save_topic_dependencies"
          params[:assignment_id] = params[:assignment_id].to_i.to_s
          topics = SignUpTopic.find_with_assignment_id( params[:assignment_id])
          topics = topics.collect { |topic|
            #if there is no dependency for a topic then there wont be a post for that tag.
            #if this happens store the dependency as "0"
            !(params['topic_dependencies_' + topic.id.to_s].nil?)?([topic.id, params['topic_dependencies_' + topic.id.to_s][:dependent_on]]):([topic.id, ["0"]])
          }
          # Save the dependency in the topic dependency table
          TopicDependency.save_dependency(topics)
          node = 'id'
          dg = build_dependency_graph(topics, node)
          if dg.acyclic?
            #This method produces sets of vertexes which should have common start time/deadlines
            set_of_topics = create_common_start_time_topics(dg)
            set_start_due_date(params[:assignment_id], set_of_topics)
            @top_sort = dg.topsort_iterator.to_a
          else
            flash[:error] = "There may be one or more cycles in the dependencies. Please correct them"
          end
          node = 'topic_name'
          dg = build_dependency_graph(topics, node) # rebuild with new node name
          graph_output_path = 'public/assets/staggered_deadline_assignment_graph'
          FileUtils::mkdir_p graph_output_path
          dg.write_to_graphic_file('jpg', "#{graph_output_path}/graph_#{params[:assignment_id]}")
          redirect_to_sign_up(params[:assignment_id])
        end


        #If the instructor needs to explicitly change the start/due dates of the topics
        #This is true in case of a staggered deadline type assignment. Individual deadlines can
        # be set on a per topic  and per round basis
        def save_topic_deadlines
          puts "2222222 call save_topic_deadlines"
          due_dates = params[:due_date]
          review_rounds = Assignment.find(params[:assignment_id]).get_review_rounds
          due_dates.each { |due_date|
            for i in 1..review_rounds
              topic_deadline_type_subm = DeadlineType.find_with_name('submission').id
              topic_deadline_type_rev = DeadlineType.find_with_name('review').id

              topic_deadline_subm = TopicDeadline.find_with_tid_and_dtype_and_round( due_date['t_id'].to_i, topic_deadline_type_subm, i).first
              topic_deadline_subm.update_attributes({'due_at' => due_date['submission_' + i.to_s]})
              flash[:error] = "Please enter a valid " + (i > 1 ? "Resubmission deadline " + (i-1).to_s : "Submission deadline") if topic_deadline_subm.errors.length > 0

              topic_deadline_rev = TopicDeadline.find_with_tid_and_dtype_and_round( due_date['t_id'].to_i, topic_deadline_type_rev, i).first
              topic_deadline_rev.update_attributes({'due_at' => due_date['review_' + i.to_s]})
              flash[:error] = "Please enter a valid Review deadline " + (i > 1 ? (i-1).to_s : "") if topic_deadline_rev.errors.length > 0
            end
            topic_deadline_subm = TopicDeadline.find_with_tid_and_dtype( due_date['t_id'],  DeadlineType.find_with_name('metareview').id).first
            topic_deadline_subm.update_attributes({'due_at' => due_date['submission_' + (review_rounds+1).to_s]})
            flash[:error] = "Please enter a valid Meta review deadline" if topic_deadline_subm.errors.length > 0
          }
          redirect_to_sign_up(params[:assignment_id])
        end

        #used by save_topic_dependencies. The dependency graph is a partial ordering of topics ... some topics need to be done
        # before others can be attempted.
        def build_dependency_graph(topics,node)
          puts "2222222 call build_denpendency_graph"
          SignUpSheet.create_dependency_graph(topics,node)
        end
        #used by save_topic_dependencies. Do not know how this works
        def create_common_start_time_topics(dg)
          puts "2222222 call create_common_start_time_topics"
          dg_reverse = dg.clone.reverse()
          set_of_topics = Array.new

          until dg_reverse.empty?
            i = 0
            temp_vertex_array = Array.new
            dg_reverse.each_vertex { |vertex|
              if dg_reverse.out_degree(vertex).zero?
                temp_vertex_array.push(vertex)
              end
            }
            #this cannot go inside the if statement above
            temp_vertex_array.each { |vertex|
              dg_reverse.remove_vertex(vertex)
            }
            set_of_topics.insert(i, temp_vertex_array)
            i = i + 1
          end
          set_of_topics
        end

        def create_topic_deadline(due_date, offset, topic_id)
          puts "2222222 call create_topic_deadline"
          DueDate.assign_topic_deadline(due_date,offset,topic_id)
        end

        def set_start_due_date(assignment_id, set_of_topics)
          puts "2222222 call set_start_due_date"
          DueDate.assign_start_due_date(assignment_id, set_of_topics)
        end

        #gets team_details to show it on team_details view for a given assignment
        def show_team
          puts "2222222 call show_team"
          if !(assignment = Assignment.find(params[:assignment_id])).nil? and !(topic = SignUpTopic.find(params[:id])).nil?
            @results =ad_info(assignment.id, topic.id)
            @results.each do |result|
              result.attributes().each do |attr|
                if attr[0].equal? "name"
                  @current_team_name = attr[1]
                end
              end
            end
            @results.each { |result|
              @team_members = ""
              TeamsUser.where(team_id: result[:team_id]).each { |teamuser|
                @team_members+=User.find(teamuser.user_id).name+" "
              }
            }
            #@team_members = find_team_members(topic)
          end
        end

        # get info related to the ad for partners so that it can be displayed when an assignment_participant
        # clicks to see ads related to a topic
        def ad_info(assignment_id, topic_id)
          puts "2222222 call ad_info"
          query = "select t.id as team_id,t.comments_for_advertisement,t.name,su.assignment_id, t.advertise_for_partner from teams t, signed_up_users s,sign_up_topics su "+
                  "where s.topic_id='"+topic_id.to_s+"' and s.creator_id=t.id and s.topic_id = su.id;    "
          SignUpTopic.find_by_sql(query)
        end

        def add_default_microtask
          puts "2222222 call add_defualt_microtask"
          assignment_id = params[:id]
          @sign_up_topic = SignUpTopic.new
          @sign_up_topic.topic_identifier = 'MT1'
          @sign_up_topic.topic_name = 'Microtask Topic'
          @sign_up_topic.max_choosers = '0'
          @sign_up_topic.micropayment = 0
          @sign_up_topic.assignment_id = assignment_id

          @assignment = Assignment.find(params[:id])

          if @assignment.staggered_deadline?
            topic_set = Array.new
            topic = @sign_up_topic.id
          end

          if @sign_up_topic.save

            flash[:notice] = 'Default Microtask topic was created - please update.'
            redirect_to_sign_up(assignment_id)
          else
            render action: 'new', id: assignment_id
          end
        end
        end
