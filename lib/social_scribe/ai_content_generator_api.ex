defmodule SocialScribe.AIContentGeneratorApi do
  @moduledoc """
  Behaviour for generating AI content for meetings.
  """

  @callback generate_follow_up_email(map()) :: {:ok, String.t()} | {:error, any()}
  @callback generate_automation(map(), map()) :: {:ok, String.t()} | {:error, any()}
  @callback generate_hubspot_suggestions(map()) :: {:ok, list(map())} | {:error, any()}
  @callback generate_salesforce_contact_updates(map(), map()) ::
              {:ok, [map()]} | {:error, any()}
  @callback generate_contact_question_answer(String.t(), [map()], opts :: keyword()) ::
              {:ok, String.t()} | {:error, any()}

  def generate_follow_up_email(meeting) do
    impl().generate_follow_up_email(meeting)
  end

  def generate_automation(automation, meeting) do
    impl().generate_automation(automation, meeting)
  end

  def generate_hubspot_suggestions(meeting) do
    impl().generate_hubspot_suggestions(meeting)
  end

  def generate_salesforce_contact_updates(meeting, contact_record) do
    impl().generate_salesforce_contact_updates(meeting, contact_record)
  end

  def generate_contact_question_answer(question, contact_data_list, opts \\ []) do
    impl().generate_contact_question_answer(question, contact_data_list, opts)
  end

  defp impl do
    Application.get_env(
      :social_scribe,
      :ai_content_generator_api,
      SocialScribe.AIContentGenerator
    )
  end
end
