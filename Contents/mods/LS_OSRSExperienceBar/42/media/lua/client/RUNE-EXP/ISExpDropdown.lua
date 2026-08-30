ISExpDropdown = ISPanel:derive("ISExpDropdown");

function ISExpDropdown:new(px, py, pw, ph)
	local dropdownPanel = {};
	dropdownPanel = ISPanel:new(px, py, pw, ph);
	setmetatable(dropdownPanel, self);
    self.__index = self;

    dropdownPanel.backgroundColor = {r=0.22, g=0.19, b=0.14, a=1.0};
    dropdownPanel.panelIsOpen = false;

	--dropdownPanel.button_w = 80;
	--dropdownPanel.button_h = 16;

	dropdownPanel.button_w = pw;
	dropdownPanel.button_h = math.floor(ph * .5);

	dropdownPanel.button_handle_hide = nil;
	dropdownPanel.button_title_hide = {[true]="Hide", [false]="Show"};

	dropdownPanel.expBar_isOpen = true;
	dropdownPanel.expBar_handle = nil;

    dropdownPanel:setCapture(false);
    return dropdownPanel;
end

function ISExpDropdown:initialize()
	ISUIElement.initialise(self);
end

--Override
function ISExpDropdown:onMouseMoveOutside(dx, dy)
	if self.panelIsOpen then
		self:setOpen(false);
	end
end

function ISExpDropdown:initChildren(expBar_handle)
	local button;
	button = ISButton:new(0, 0, self.button_w, self.button_h, self.button_title_hide[self.expBar_isOpen], self, ISExpDropdown.toggleExpBar);
	button:initialise();
	button.backgroundColor = 	{r=0.22, g=0.19, b=0.14, a=1.0};
	button:setVisible(self.panelIsOpen);

	self:addChild(button);
	self.button_handle_hide = button;

	button = ISButton:new(0, self.button_h, self.button_w, self.button_h, "Configurate", self, ISExpDropdown.openConfig);
	button:initialise();
	button.backgroundColor = 	{r=0.22, g=0.19, b=0.14, a=1.0};
	button:setVisible(self.panelIsOpen);

	self:addChild(button);

	self.expBar_handle = expBar_handle;
end

function ISExpDropdown:openConfig()
	if self.expBar_handle ~= nil then
		self.expBar_handle:openConfigPanel();
	end

	self:setOpen(false, nil, nil);
end

function ISExpDropdown:toggleExpBar()
	if self.expBar_handle ~= nil then
		self.expBar_isOpen = not self.expBar_isOpen;
		self.expBar_handle:setButtonMode(not self.expBar_isOpen, false);
		self:updateHideButton();
	end

	self:setOpen(false, nil, nil);
end

function ISExpDropdown:updateHideButton()
	if self.button_handle_hide ~= nil then
		self.button_handle_hide:setTitle(self.button_title_hide[self.expBar_isOpen]);
	end
end

function ISExpDropdown:toggleOpen()
	self:setOpen(not self.panelIsOpen, nil, nil);
end

function ISExpDropdown:getOpen()
	return self.panelIsOpen;
end

function ISExpDropdown:setOpen(isOpen, px, py)
	self.panelIsOpen = isOpen;
	self:setVisible(isOpen);

	local children;
	children = self:getChildren();

	for child_key, child in pairs(children) do
		child:setVisible(isOpen);
	end

	if isOpen then
		self:bringToTop();

		if px ~= nil then
			self:setX(px);
		end

		if py ~= nil then
			self:setY(py);
		end
	end
end