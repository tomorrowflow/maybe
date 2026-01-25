class TagsController < ApplicationController
  before_action :set_tag, only: %i[edit update destroy]

  def index
    @tags = Current.family.tags.alphabetically

    render layout: "settings"
  end

  def new
    @tag = Current.family.tags.new color: Tag::COLORS.sample
  end

  def create
    @tag = Current.family.tags.new(tag_params)

    if @tag.save
      redirect_to tags_path, notice: t(".created")
    else
      redirect_to tags_path, alert: t(".error", error: @tag.errors.full_messages.to_sentence)
    end
  end

  def edit
  end

  def update
    @tag.update!(tag_params)
    redirect_to tags_path, notice: t(".updated")
  end

  def destroy
    @tag.destroy!
    redirect_to tags_path, notice: t(".deleted")
  end

  def destroy_all
    Current.family.tags.destroy_all
    redirect_back_or_to tags_path, notice: "All tags deleted"
  end

  def reprocess
    # Find transactions without tags
    untagged = Current.family.transactions
      .left_joins(:taggings)
      .where(taggings: { id: nil })

    if untagged.none?
      # If all transactions have tags, reprocess all of them
      untagged = Current.family.transactions
    end

    if untagged.any?
      Current.family.auto_tag_transactions_later(untagged)
      redirect_back_or_to tags_path, notice: t(".reprocess_success", count: untagged.count)
    else
      redirect_back_or_to tags_path, alert: t(".no_transactions")
    end
  end

  private

    def set_tag
      @tag = Current.family.tags.find(params[:id])
    end

    def tag_params
      params.require(:tag).permit(:name, :color)
    end
end
