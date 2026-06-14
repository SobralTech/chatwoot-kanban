class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy, :send_response]

  def index
    render json: serialize_canned_responses(canned_responses)
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params)
    assign_steps(@canned_response)
    @canned_response.save!
    render json: serialize_canned_response(@canned_response)
  end

  def update
    @canned_response.assign_attributes(canned_response_params)
    assign_steps(@canned_response)
    @canned_response.save!
    render json: serialize_canned_response(@canned_response)
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  def send_response
    conversation = Current.account.conversations.find_by!(
      display_id: params[:conversation_id]
    )
    messages = CannedResponses::QuickSendService.new(
      user: Current.user,
      conversation: conversation,
      canned_response: @canned_response
    ).perform

    render json: messages.map(&:push_event_data)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  private

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content, :mode)
  end

  def assign_steps(canned_response)
    return clear_steps(canned_response) if canned_response.mode == 'insert'
    return unless steps_provided?

    canned_response.canned_response_steps.destroy_all if canned_response.persisted?
    build_steps(canned_response)
    canned_response.content = fallback_content(canned_response) if canned_response.content.blank?
  end

  def clear_steps(canned_response)
    canned_response.canned_response_steps.destroy_all if canned_response.persisted?
  end

  def steps_provided?
    params[:canned_response]&.key?(:steps)
  end

  def build_steps(canned_response)
    parsed_steps.each do |step_params|
      step = canned_response.canned_response_steps.build(
        step_type: step_params[:step_type],
        content: step_params[:content],
        position: step_params[:position]
      )
      attach_step_file(step, step_params)
    end
  end

  def parsed_steps
    steps = params[:canned_response][:steps]
    steps = JSON.parse(steps) if steps.is_a?(String)
    steps.map.with_index do |step, index|
      step_params_hash(step)
        .slice(:step_type, :content, :position, :file_key, :file_blob_id)
        .tap do |step_params|
        step_params[:position] = index if step_params[:position].blank?
      end
    end
  end

  def step_params_hash(step)
    return step.to_unsafe_h.with_indifferent_access if step.respond_to?(:to_unsafe_h)

    step.with_indifferent_access
  end

  def attach_step_file(step, step_params)
    return unless step.media?

    if step_params[:file_key].present? &&
       params[:step_files]&.[](step_params[:file_key]).present?
      step.file.attach(params[:step_files][step_params[:file_key]])
    elsif step_params[:file_blob_id].present?
      step.file.attach(step_params[:file_blob_id])
    end
  end

  def fallback_content(canned_response)
    canned_response.canned_response_steps.find(&:text?)&.content || canned_response.short_code
  end

  def serialize_canned_responses(records)
    records.map { |record| serialize_canned_response(record) }
  end

  def serialize_canned_response(record)
    record.as_json.merge(
      'steps' => record.canned_response_steps.ordered.map do |step|
        step.as_json(methods: [:file_url, :file_name, :file_blob_id])
      end
    )
  end

  def canned_responses
    if params[:search]
      Current.account.canned_responses
             .includes(canned_response_steps: { file_attachment: :blob })
             .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
             .order_by_search(params[:search])

    else
      Current.account.canned_responses
             .includes(canned_response_steps: { file_attachment: :blob })
    end
  end
end
