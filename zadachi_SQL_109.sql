-- 720. «Товар із перевернутим профілем клієнта»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by avg_chek) FROM level2) as median_chek
FROM level3),
level5 as(SELECT *
       ,case when avg_chek < median_chek THEN 'low_chek_customer'
	   else 'other' END as gradation
FROM level4
ORDER BY customer_id)
SELECT *
FROM level5
WHERE gradation = 'low_chek_customer'),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id))
SELECT *
       ,SUM(quantity) OVER (partition by product_id) as total_quantity
FROM level1),
block3 as(SELECT *
       ,SUM(quantity) FILTER (WHERE gradation = 'low_chek_customer') OVER (partition by product_id) as sum_quantity_low_chek_customer
FROM block1 
JOIN block2 USING (customer_id, order_id)
ORDER BY customer_id),
block4 as(SELECT * 
       ,ROUND((sum_quantity_low_chek_customer::numeric / total_quantity::numeric),4) as ratio
FROM block3)
SELECT *
FROm block4
WHERE ratio >= 0.6

-- 721. «Клієнт із хибною стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,STDDEV(sum_chek) OVER (partition by customer_id) as stddev_chek
FROM level1
WHERE count_order >= 8)
SELECT *
FROM level2
WHERE stddev_chek = 0

-- 722. «Клієнт із ілюзією зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date, order_id) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC, order_id DESC) as rn_invert
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,case when rn <= 3 THEN 'first_3_order'
	   when rn_invert <= 3 THEN 'last_3_order'
	   else 'other' END as gradation
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'first_3_order') OVER (partition by customer_id)::numeric,2) as avg_chek_first_3_order
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'last_3_order') OVER (partition by customer_id)::numeric,2) as avg_chek_last_3_order
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'other') OVER (partition by customer_id)::numeric,2) as avg_chek_middle_orders
FROm level3)
SELECT *
FROM level4
WHERE avg_chek_first_3_order > avg_chek_last_3_order
AND avg_chek = avg_chek_middle_orders

-- 723. «Клієнт із ефектом накопиченої пам’яті»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,MAX(case when sum_chek = max_chek THEN order_date END) OVER (partition by customer_id) as date_max_chek
FROM level2),
level4 as(SELECT *
       ,case when order_date < date_max_chek THEN 'before_group'
	   when order_date > date_max_chek THEN 'after_group'
	   when order_date = date_max_chek THEN 'date_peak'
	   END as gradation
FROM level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'before_group')::numeric,2) as avg_chek_before_group
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'after_group')::numeric,2) as avg_chek_after_group
FROM level4
GROUP By customer_id)
SELECT *
FROM level5
WHERE avg_chek_before_group is not null AND avg_chek_after_group is not null
AND avg_chek_after_group > avg_chek_before_group

-- 724. «Клієнт із прихованою ентропією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn  
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn IN (2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40) THEN 'paar'
	   else 'not_paar' END as gradation
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as next_chek
FROM level2),
level4 as(SELECT *
       ,case when sum_chek > next_chek AND gradation = 'not_paar' THEN 1 ELSE 0 END as not_paar_high_paar
	   ,case when sum_chek > next_chek AND gradation = 'paar' THEN 1 ELSE 0 END as paar_high_not_paar
	   ,COUNT(order_id) FILTER (WHERE gradation = 'not_paar') OVER (partition by customer_id) as count_not_paar
	   ,COUNT(order_id) FILTER (WHERE gradation = 'paar') OVER (partition by customer_id) as count_paar
FROM level3
WHERE next_chek is not null),
level5 as(SELECT *
       ,SUM(not_paar_high_paar) OVER (partition by customer_id) as sum_not_paar_high_paar
	   ,SUM(paar_high_not_paar) OVER (partition by customer_id) as sum_paar_high_not_paar
FROm level4)
SELECT *
FROM level5
WHERE sum_not_paar_high_paar = count_not_paar OR sum_paar_high_not_paar = count_paar

-- 724. «Клієнт із прихованою ентропією» - 2 спосіб, про рівність чеків по парних і непарних замовленнях

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn  
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn IN (2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40) THEN 'paar'
	   else 'not_paar' END as gradation
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'paar')::numeric,2) as avg_chek_paar
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation ='not_paar')::numeric,2) as avg_chek_not_paar
FROM level2
GROUP By customer_id)
SELECT *
FROm level3
WHERE avg_chek_paar = avg_chek_not_paar

