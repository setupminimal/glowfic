module SpecNPlusOneHelper
  # Runs the block (typically a request or controller action) with Prosopite configured to raise,
  # so the example fails if the block triggers an N+1 query.
  # Controllers are scanned by an around_action, so the error is raised when the action finishes.
  def expect_no_n_plus_one
    original = Prosopite.instance_variable_get(:@raise) # Prosopite only exposes a writer
    Prosopite.raise = true
    yield
  ensure
    Prosopite.raise = original
  end
end
