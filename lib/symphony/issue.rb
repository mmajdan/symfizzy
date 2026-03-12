module Symphony
  Issue = Struct.new(
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :labels,
    :blocked_by,
    :created_at,
    :updated_at,
    keyword_init: true
  ) do
    def to_template_payload
      {
        "id" => id,
        "identifier" => identifier,
        "title" => title,
        "description" => description,
        "priority" => priority,
        "state" => state,
        "branch_name" => branch_name,
        "url" => url,
        "labels" => labels,
        "blocked_by" => blocked_by,
        "created_at" => created_at,
        "updated_at" => updated_at
      }
    end
  end
end
