-- 230. “Клієнти з нестабільною ціною”

WITH level1 as(SELECT customer_id
       ,product_id
       ,order_id
	   ,ROUND((p.unit_price * (1-discount))::numeric,2) as price_bevor_discount
FROM orders
JOIn order_details USING(order_id)
JOIN products p USING(product_id)),
level2 as(SELECT customer_id
       ,MIN(price_bevor_discount) as min_price_bevor_discount
	   ,MAX(price_bevor_discount) as max_price_bevor_discount
	   ,COUNT(DISTINCT product_id) as count_dst_prod
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND((max_price_bevor_discount - min_price_bevor_discount)::numeric,2) as range
FROM level2)
SELECT *
FROM level3
WHERE range >= 50 AND count_dst_prod >= 5

-- 231. “Клієнти з різким ціновим контрастом усередині замовлень”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND((p.unit_price * (1-discount))::numeric,2) as price_after_discount	
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)),
level2 as(SELECT *
       ,MAX(price_after_discount) OVER (partition by customer_id,order_id) as max_order_price
	   ,MIN(price_after_discount) OVER (partition by customer_id,order_id) as min_order_price
FROM level1),
level3 as(SELECT *
       ,max_order_price - min_order_price as order_price_range
FROM level2),
level4 as(SELECT DISTINCT order_id
       ,customer_id
	   ,max_order_price
	   ,min_order_price
	   ,order_price_range
FROM level3),
level5 as(SELECT customer_id
      ,ROUND(AVG(order_price_range)::numeric,2) as avg_price_range
	  ,MAX(order_price_range) as max_price_range
	  ,COUNT(*) as count_order
FROM level4
GROUP BY customer_id
ORDER BY customer_id)
SELECT *
FROM level5
WHERE max_price_range >= 40 AND count_order >= 3

-- 232. Знайти клієнтів, у яких категорія з найбільшою кількістю замовлень
-- не збігається з категорією, що дає найбільший сумарний оборот.

WITH level1 as(SELECT customer_id
       ,category_name
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY customer_id, category_name),
level2 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by sum_quantity DESC) as rank_quantity
	   ,ROW_NUMBER() OVER (partition by customer_id order by sum_chek DESC) as rank_chek
FROm level1),
level3 as(SELECT *
FROM level2
WHERE rank_quantity <> rank_chek)
SELECT *
FROM level3
WHERE rank_quantity = 1 OR rank_chek = 1

-- рішення від чатіка (для тупих гуманітаріїв)

WITH level1 AS (
    SELECT customer_id
          ,category_name
          ,SUM(quantity) AS sum_quantity
          ,ROUND(SUM(p.unit_price * quantity * (1 - discount))::numeric, 2) AS sum_chek
    FROM orders
    JOIN order_details USING(order_id)
    JOIN products p USING(product_id)
    JOIN categories USING(category_id)
    GROUP BY customer_id, category_name
),

level2 AS (
    SELECT *
          ,DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY sum_quantity DESC) AS rank_quantity
          ,DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY sum_chek DESC)     AS rank_chek
    FROM level1
),

-- відкидаємо клієнтів з кількома топами
level3 AS (
    SELECT customer_id
    FROM level2
    GROUP BY customer_id
    HAVING COUNT(*) FILTER (WHERE rank_quantity = 1) = 1
       AND COUNT(*) FILTER (WHERE rank_chek = 1) = 1
),

-- беремо тільки дві топ-категорії
level4 AS (
    SELECT l2.customer_id
          ,l2.category_name
          ,CASE 
               WHEN rank_quantity = 1 THEN 'top_by_quantity'
               WHEN rank_chek = 1 THEN 'top_by_revenue'
           END AS top_type
    FROM level2 l2
    JOIN level3 l3 USING(customer_id)
    WHERE rank_quantity = 1 OR rank_chek = 1
)

SELECT customer_id
      ,MAX(category_name) FILTER (WHERE top_type = 'top_by_quantity') AS top_category_by_quantity
      ,MAX(category_name) FILTER (WHERE top_type = 'top_by_revenue')  AS top_category_by_revenue
FROM level4
GROUP BY customer_id
HAVING
    MAX(category_name) FILTER (WHERE top_type = 'top_by_quantity')
    <>
    MAX(category_name) FILTER (WHERE top_type = 'top_by_revenue');

-- 232. Знайти клієнтів, у яких перша і остання категорія покупок різні,
-- але між ними є хоча б одна повторна покупка першої категорії.

WITH level1 as(SELECT customer_id
       ,order_date
	   ,category_name
	   ,FIRST_VALUE(category_name) OVER (partition by customer_id order by order_date) as first_category
	   ,FIRST_VALUE(category_name) OVER (partition by customer_id order by order_date DESC) as last_category
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)),
level2 as(SELECT *
       ,case when category_name = first_category THEN 1 ELSE 0 END as flag_category
FROM level1),
level3 as(SELECT *
       ,SUM(flag_category) OVER (partition by customer_id) as sum_flag_category
FROM level2),
level4 as(SELECT customer_id
       ,order_date
       ,category_name
	   ,first_category
	   ,last_category
	   ,sum_flag_category
FROM level3),
level5 as(SELECT customer_id
       ,COUNT(DISTINCT order_id) as count_dist_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id),
level6 as(SELECT *
FROM level4
JOIN level5 USING(customer_id))
SELECT *
FROM level6
WHERE first_category <> last_category AND sum_flag_category >= 2 AND count_dist_order >= 3

-- 233. Знайти клієнтів, у яких найбільший інтервал між замовленнями припадає НЕ на початок і НЕ 
-- на кінець історії, а всередину.

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
       ,order_id
FROM orders 
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROm level1),
level3 as(SELECT *
       ,NTILE(3) OVER (partition by customer_id order by order_date) as ntile
FROm level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,CASE when ntile = 1 THEN '1_beginning'
	   when ntile = 2 THEN '2_middle'
	   when ntile = 3 THEN '3_end'
	   END as gradation
FROm level3),
level5 as(SELECT *
       ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROm level4),
level6 as(SELECT *
       ,order_date - prev_date as interval
FROM level5),
level7 as(SELECT customer_id
       ,MAX(interval) FILTER (where gradation = '1_beginning') as max_begin
	   ,MAX(interval) FILTER (where gradation = '2_middle') as max_middle
	   ,MAX(interval) FILTER (where gradation = '3_end') as max_end
FROm level6
WHERE interval is not null
GROUP By customer_id),
level8 as(SELECT *
       ,case when max_middle>max_begin AND max_middle>max_end THEN 'yes'
	   ELSE 'no' END as flag
FROm level7)
SELECT *
FROM level8
WHERE flag = 'yes' 

-- 234. Знайти клієнтів, у яких після найдовшої паузи перші 2 замовлення після повернення
-- мають менший середній розмір кошика, ніж 2 замовлення ДО цієї паузи.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROM level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level3),
level5 as(SELECT *
       ,MAX(order_date) FILTER (where interval = max_interval) OVER(partition by customer_id) as pause_order_date
FROM level4
WHERE interval is not null),
level6 as(SELECT *
       ,case when order_date < pause_order_date THEN '1_bevor_pause'
	   when order_date >= pause_order_date THEN '2_after_pause'
	   END as gradation
FROm level5),
level7 as(SELECT *
       ,case when gradation = '1_bevor_pause' THEN ROW_NUMBER() OVER (partition by customer_id,gradation order by order_date DESC) END as rn_bevor
	   ,case when gradation = '2_after_pause' THEN ROW_NUMBER() OVER (partition by customer_id,gradation order by order_date ASC) END as rn_after
FROM level6
WHERE gradation IN ('1_bevor_pause','2_after_pause')),
level8 as(SELECT *
FROM level7
WHERE rn_bevor <=2 OR rn_after <=2),
level9 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '1_bevor_pause')::numeric,2) as avg_qnt_bevor_pause
	   ,COUNT(*) FILTER (WHERE gradation = '1_bevor_pause') as count_order_bevor_pause
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = '2_after_pause')::numeric,2) as avg_qnt_after_pause
	   ,COUNT(*) FILTER (WHERE gradation = '2_after_pause') as count_order_after_pause
FROM level8
GROUP BY customer_id)
SELECT *
FROM level9
WHERE count_order_bevor_pause=2 AND count_order_after_pause = 2 AND avg_qnt_bevor_pause > avg_qnt_after_pause
