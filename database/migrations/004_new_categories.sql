INSERT INTO categories (name, parent_id, level, description)
SELECT t.name, c.id, 2, t.description
FROM (VALUES
    ('Consumer Electronics', 'Technology',      'Hardware devices sold to end consumers (smartphones, tablets, wearables)'),
    ('Cloud & Infrastructure', 'Technology',    'Cloud platforms, CDN, networking and data-center infrastructure'),
    ('Retail',               'Consumer',        'Brick-and-mortar and omnichannel retail chains'),
    ('REITs',                'Real Estate',     'Publicly traded real estate investment trusts')
) AS t(name, parent_name, description)
JOIN categories c ON c.name = t.parent_name;
