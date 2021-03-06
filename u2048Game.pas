unit u2048Game;

interface

uses
  Windows, Generics.Collections, Types;

const
  GridWidth = 4;
  GridMax = GridWidth - 1;

type
  TGameState = (gsPlaying, gsWon, gsLost, gsSandbox);
  TDirection = (dLeft, dRight, dUp, dDown);

  TCell = class
  protected
    FValue: Integer;
    FPosition, FOldPosition: TPoint;
    procedure SetPosition(Point: TPoint);
  public
    property Value: Integer read FValue;
    property Position: TPoint read FPosition;
    property OldPosition: TPoint read FOldPosition;
  end;

  TCellList = TList<TCell>;
  TPointList = TList<TPoint>;

  TGame = class
  private
    FNewCell: TCell;
    FScore: Integer;
  protected
    // The grid of cells.
    FBoard: array[0..GridMax,0..GridMax] of TCell;
    // A list of free positions on the grid on which new values can be spawned.
    FFreeLocations: TPointList;
    FState: TGameState;
    // Get a cell from the board, based on the row and column positions in a given direction.
    function GetCell(Row, Column: Integer; Direction: TDirection; out Cell: TCell): Boolean; overload;
    // Get a row of cells from the board. Empty cells are skipped.
    procedure GetRow(RowIndex: Integer; Direction: TDirection; Row: TCellList; out HasEmptyCellsInbetween: Boolean);
    // Collapse a list of cellsl
    function CollapseRow(Row: TCellList): Boolean;
    // Write a collapsed row back to the board and update the list of free cells.
    procedure UpdateBoard(Row: TCellList; RowIndex: Integer; Direction: TDirection);

    // Translate a row and column position in a given direction to absolute grid coordinates.
    procedure Normalize(Row, Column: Integer; Direction: TDirection; out X, Y: Integer);

    // Get a random value for a new cell.
    function GetSpawnValue: Integer;
    // Spawn a cell.
    procedure SpawnAt(Point: TPoint; Value: Integer);

    // Check the end-game conditions and update the game state.
    procedure CheckEndConditions;

    // Clear the board.
    procedure Clear;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    // Start the game.
    procedure Start;
    procedure Continue;
    // Slide the board in a given direction. Returns false if nothing moved or collapsed.
    function Move(Direction: TDirection): Boolean;
    // Get a cell at the given position. Returns false if that grid position is empty.
    function GetCell(X, Y: Integer; out Cell: TCell): Boolean; overload;
    property NewCell: TCell read FNewCell;

    // The game state.
    property State: TGameState read FState;
    property Score: Integer read FScore;
  end;

implementation

procedure Swap(var A, B: Integer);
var C: Integer;
begin
  C := A; A := B; B := C;
end;

{ TGame }

procedure TGame.CheckEndConditions;
const
  // Checking in two directions is enough.
  CheckDirections: array[0..1] of TDirection = (dRight, dDown);
var
  DirectionIndex, RowIndex, ColIndex: Integer;
  Row: TCellList;
  CanCollapseOrMove, HasEmptyCellsInbetween: Boolean;
begin
  // Be able to continue playing in sandbox mode after you've won.
  if FState = gsSandbox then
    Exit;

  CanCollapseOrMove := False;

  Row := TCellList.Create;
  try
    for DirectionIndex := Low(CheckDirections) to High(CheckDirections) do
      for RowIndex := 0 to GridMax do
      begin
        // Get the non-empty cells of each row.
        GetRow(RowIndex, CheckDirections[DirectionIndex], Row, HasEmptyCellsInbetween);

        // If any of the cells has the winning value, the game is won.
        for ColIndex := 0 to Row.Count - 1 do
          if Row[ColIndex].Value = 2048 then
            FState := gsWon;

        // If not won, check the row to see if you can still move.
        if FState = gsPlaying then
        begin
          if Row.Count < GridWidth then // Find a free cell.
            CanCollapseOrMove := True
          else // Find collapsable cells
            for ColIndex := 1 to Row.Count - 1 do
              if (Row[ColIndex].FValue = Row[ColIndex - 1].FValue) then
                CanCollapseOrMove := True;
        end;

        Row.Clear;
        // Todo: Nested loop might be early exited if the game is won. Hardly worth it.
      end;

    // Still playing and cannot move? Game is lost.
    if (fState = gsPlaying) and not CanCollapseOrMove then
      FState := gsLost;

  finally
    Row.Free;
  end;
end;

procedure TGame.Clear;
var
  X, Y: Integer;
begin
  for X := 0 to GridMax do
    for Y := 0 to GridMax do
    begin
      FBoard[X, Y].Free;
      FBoard[X, Y] := nil;
    end;
end;

function TGame.CollapseRow(Row: TCellList): Boolean;
var
  ColIndex: Integer;
begin
  // Collapse a row by adding up adjacent cells with the same value.
  Result := False;
  ColIndex := 1;
  while ColIndex < Row.Count do
  begin
    if Row[ColIndex].FValue = Row[ColIndex - 1].FValue then
    begin
      Result := True;
      // Todo: Keep the old value for animations.
      Row[ColIndex].FValue := Row[ColIndex].FValue shl 1;
      FScore := FScore + Row[ColIndex].FValue;
      // Todo: Keep the cell for animations.
      Row[ColIndex - 1].Free;
      Row.Delete(ColIndex - 1);
    end;
    Inc(ColIndex);
  end;
end;

procedure TGame.Continue;
begin
  // Continue playing in sandbox mode.
  if FState = gsWon then
    FState := gsSandbox;
end;

constructor TGame.Create;
begin
  FFreeLocations := TPointList.Create;
  Start;
end;

destructor TGame.Destroy;
begin
  Clear;
  FFreeLocations.Free;
  inherited;
end;

function TGame.GetCell(Row, Column: Integer; Direction: TDirection;
  out Cell: TCell): Boolean;
var
  X, Y: Integer;
begin
  Normalize(Row, Column, Direction, X, Y);
  Result := GetCell(X, Y, Cell);
end;

function TGame.GetCell(X, Y: Integer; out Cell: TCell): Boolean;
begin
  Cell := FBoard[X, Y];
  Result := Cell <> nil;
end;

procedure TGame.GetRow(RowIndex: Integer; Direction: TDirection; Row: TCellList; out HasEmptyCellsInbetween: Boolean);
var
  ColIndex: Integer;
  Cell: TCell;
  EmptyCellFound: Boolean;
begin
  HasEmptyCellsInbetween := False;
  EmptyCellFound := False;
  // Populate a list with all cells of the row.
  for ColIndex := 0 to GridMax do
    if GetCell(RowIndex, ColIndex, Direction, Cell) then
    begin
      Row.Add(Cell);
      if EmptyCellFound then
        HasEmptyCellsInbetween := True;
    end
    else
      EmptyCellFound := True;
end;

function TGame.GetSpawnValue: Integer;
begin
  // One in ten will be a 4. The others will be 2.
  if Random(10) = 0 then
    Result := 4
  else
    Result := 2;
end;

function TGame.Move(Direction: TDirection): Boolean;
var
  Row: TCellList;
  RowIndex: Integer;
  HasEmptyCellsInbetween: Boolean;
begin
  Result := False;

  FFreeLocations.Clear;

  Row := TCellList.Create;
  try
    for RowIndex := 0 to GridMax do
    begin
      GetRow(RowIndex, Direction, Row, HasEmptyCellsInbetween);

      if HasEmptyCellsInbetween then
        Result := True;

      // Collapse each of the rows.
      if CollapseRow(Row) then
        Result := True;

      // Update the grid.
      UpdateBoard(Row, RowIndex, Direction);

      Row.Clear;
    end;

  finally
    Row.Free;
  end;

  if Result then
  begin
    // If there was movement or collapse, there should always be a free cell.
    Assert(FFreeLocations.Count > 0);
    // Spawn a new value.
    SpawnAt(FFreeLocations[Random(FFreeLocations.Count)], GetSpawnValue);
    // Check if we've won or lost yet.
    CheckEndConditions;
  end;
end;

procedure TGame.Normalize(Row, Column: Integer; Direction: TDirection; out X,
  Y: Integer);
begin
  // Direction is the direction in which stuff is moving, so we start counting
  // from that direction. That means that:
  // When moving down or right, inverse the column index to count from the far end.
  if Direction in [dDown, dRight] then
    Column := GridMax - Column;
  // When moving up or down, swap row and column, to have vertical rows.
  if Direction in [dUp, dDown] then
    Swap(Row, Column);
  X := Column;
  Y := Row;
end;

procedure TGame.SpawnAt(Point: TPoint; Value: Integer);
begin
  // Create a cell at the given position and initialize it with the value.
  FNewCell := TCell.Create;
  FNewCell.FValue := Value;
  FNewCell.SetPosition(Point);
  FNewCell.SetPosition(Point); // Twice, hack to also set oldposition
  FBoard[Point.X, Point.Y] := FNewCell;
end;

procedure TGame.Start;
var
  Value: Integer;
begin
  // Clear any running game.
  Clear;
  // Todo: find out if both starting cells always have the same value in the
  // original game.
  Value := GetSpawnValue;
  // Todo: Choose random positions.
  SpawnAt(Point(0, 0), Value);
  SpawnAt(Point(0, 1), Value);
  FState := gsPlaying;
end;

procedure TGame.UpdateBoard(Row: TCellList; RowIndex: Integer;
  Direction: TDirection);
var
  ColIndex: Integer;
  X, Y: Integer;
begin
  // Update the board by simply resetting all cells in the board.
  // Todo: Remember the old positions for animations.
  for ColIndex := 0 to GridMax do
  begin

    // Translate column and row to actual grid position.
    Normalize(RowIndex, ColIndex, Direction, X, Y);

    // Set the cell on the board, or make it empty if there are no more cells
    // in the row.
    if ColIndex >= Row.Count then
    begin
      FBoard[X, Y] := nil;
      FFreeLocations.Add(Point(X, Y));
    end else
    begin
      FBoard[X, Y] := Row[ColIndex];
      Row[ColIndex].SetPosition(Point(X, Y));
    end;
  end;
end;

{ TCell }

procedure TCell.SetPosition(Point: TPoint);
begin
  FOldPosition := FPosition;
  FPosition := Point;
end;

end.
