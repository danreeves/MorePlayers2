-- luacheck: globals get_mod EndViewStateScore
local mod = get_mod("MorePlayers2")

mod:hook(EndViewStateScore, "_set_topic_data", function (func, self, player_data, widget_index)
  local widget = self._score_widgets[widget_index]
  -- Check we will get a widget before we run the function
  if not widget then
    return
  else
    return func(self, player_data, widget_index)
  end
end)

mod:hook(EndViewStateScore, "_setup_player_scores", function (func, self, players_session_scores)
  -- Limit it to the first four players
  -- TODO: Use table.slice?
  local scores = {}
  for i = 1, 4, 1 do
    scores[i] = players_session_scores[i]
  end
  return func(self, scores)
end)

mod:hook(EndViewStateScore, "_setup_score_panel", function (func, self, score_panel_scores, player_names)
  -- Limit it to the first four players
  -- TODO: Use table.slice?
  local scores = {}
  local names = {}
  for i = 1, 4, 1 do
    scores[i] = score_panel_scores[i]
    names[i] = player_names[i]
  end
  return func(self, scores, names)
end)
