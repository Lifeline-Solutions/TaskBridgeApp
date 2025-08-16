# Maps classes to short type keys for activities. Override map to customize.
module ActivityMorphMap
  module_function

  # Customize this map if you want shorter keys than full class names
  MAP = {
    'User' => 'user',
    'Project' => 'project',
    'Task' => 'task',
    'Ticket' => 'ticket',
    'Comment' => 'comment',
    'Message' => 'message',
    'Issue' => 'issue',
    'Notification' => 'notification',
    'Milestone' => 'milestone',
    'Board' => 'board',
    'Team' => 'team',
    'Client' => 'client',
    'Product' => 'product',
    'Software' => 'software',
    'Groupware' => 'groupware',
    'Status' => 'status',
    'State' => 'state',
    'Role' => 'role',
    'Document' => 'document',
    'DataCenter' => 'data_center',
    'Script' => 'script',
    'Defect' => 'defect',
    'QaModule' => 'qa_module',
    'Rating' => 'rating',
    'BankingType' => 'banking_type',
    'Event' => 'event',
    'SystemActivity' => 'system_activity'
  }.freeze

  def class_to_key(klass)
    return nil unless klass
    MAP[klass.name] || klass.name
  end
end
